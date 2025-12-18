#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x

# make errors fatal
set -e

# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(pwd)"
stage="$(pwd)/stage"

# Get version from git describe in the submodule
pushd "$top/velopack"
VELOPACK_VERSION="$(git describe --tags --always 2>/dev/null || echo "0.0.0")"
popd

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# Ensure cargo is in PATH
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
elif [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

build=${AUTOBUILD_BUILD_ID:=0}

# prepare the staging dirs
mkdir -p "$stage/LICENSES"
mkdir -p "$stage/include/velopack"
mkdir -p "$stage/lib/release"

VELOPACK_DIR="$top/velopack"
LIBCPP_DIR="$VELOPACK_DIR/src/lib-cpp"

case "$AUTOBUILD_PLATFORM" in
    windows*)
        load_vsvars

        # Build using cargo
        pushd "$VELOPACK_DIR"
        cargo build --release -p velopack_libc
        popd

        # copy libs
        cp -a "$VELOPACK_DIR/target/release/velopack_libc.dll" "$stage/lib/release/"
        cp -a "$VELOPACK_DIR/target/release/velopack_libc.dll.lib" "$stage/lib/release/" 2>/dev/null || true
        cp -a "$VELOPACK_DIR/target/release/velopack_libc.lib" "$stage/lib/release/" 2>/dev/null || true
    ;;
    darwin*)
        # Build using cargo
        pushd "$VELOPACK_DIR"
        cargo build --release -p velopack_libc
        popd

        # copy libs
        cp -a "$VELOPACK_DIR/target/release/libvelopack_libc.dylib" "$stage/lib/release/"
        cp -a "$VELOPACK_DIR/target/release/libvelopack_libc.a" "$stage/lib/release/"

        # Make sure libs are stamped with the -id
        pushd "$stage/lib/release"
        fix_dylib_id "libvelopack_libc.dylib" || \
        echo "fix_dylib_id libvelopack_libc.dylib failed, proceeding"

        if [[ -z "${build_secrets_checkout:-}" ]]
        then
            echo '$build_secrets_checkout not set; skipping codesign' >&2
        else
            CONFIG_FILE="$build_secrets_checkout/code-signing-osx/config.sh"
            if [[ ! -f "$CONFIG_FILE" ]]; then
                echo "No config file found; skipping codesign."
            else
                source $CONFIG_FILE
                codesign --force --timestamp --sign "$APPLE_SIGNATURE" "libvelopack_libc.dylib"
            fi
        fi
        popd
    ;;
    linux*)
        # Build using cargo
        pushd "$VELOPACK_DIR"
        cargo build --release -p velopack_libc
        popd

        # copy libs
        cp -a "$VELOPACK_DIR/target/release/libvelopack_libc.so" "$stage/lib/release/"
        cp -a "$VELOPACK_DIR/target/release/libvelopack_libc.a" "$stage/lib/release/"
    ;;
esac

# copy headers
cp -a "$LIBCPP_DIR/include/Velopack.h" "$stage/include/velopack/"
cp -a "$LIBCPP_DIR/include/Velopack.hpp" "$stage/include/velopack/"

echo "$VELOPACK_VERSION.$build" > "$stage/VERSION.txt"
cp "$VELOPACK_DIR/LICENSE" "$stage/LICENSES/velopack.txt"
