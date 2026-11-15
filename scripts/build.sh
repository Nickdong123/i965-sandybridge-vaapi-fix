#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$REPO_ROOT/build"
OUT_DIR="$REPO_ROOT/out"
PATCH_FILE="$REPO_ROOT/patches/0001-sandybridge-edge-vaapi-h264-vpp-export-fix.patch"

echo "=== Building i965 Sandy Bridge VA-API Patched Driver ==="

# Check build dependencies
MISSING_DEPS=()
for cmd in gcc make pkg-config; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "ERROR: Missing build tools: ${MISSING_DEPS[*]}"
    echo "Please install them via: sudo apt install build-essential pkg-config libva-dev libdrm-dev libx11-dev libgl1-mesa-dev"
    exit 1
fi

mkdir -p "$BUILD_DIR" "$OUT_DIR"
cd "$BUILD_DIR"

TARBALL="intel-vaapi-driver-2.4.1.tar.bz2"
TARBALL_URL="https://github.com/intel/intel-vaapi-driver/releases/download/2.4.1/intel-vaapi-driver-2.4.1.tar.bz2"

if [ ! -f "$TARBALL" ]; then
    echo "--> Downloading intel-vaapi-driver 2.4.1 source..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$TARBALL" "$TARBALL_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$TARBALL" "$TARBALL_URL"
    else
        echo "ERROR: Neither curl nor wget found."
        exit 1
    fi
fi

SRC_DIR="$BUILD_DIR/intel-vaapi-driver-2.4.1"
rm -rf "$SRC_DIR"
echo "--> Extracting source..."
tar -xjf "$TARBALL"

cd "$SRC_DIR"
echo "--> Applying Sandy Bridge Gen6 VPP & Buffer Allocation Patch..."
patch -p1 < "$PATCH_FILE"

echo "--> Configuring..."
./configure --prefix="$OUT_DIR"

echo "--> Compiling with $(nproc) jobs..."
make -j"$(nproc)"

echo "--> Copying compiled driver to $OUT_DIR/i965_drv_video.so..."
cp -v src/.libs/i965_drv_video.so "$OUT_DIR/i965_drv_video.so"

echo "=== Build Complete! ==="
echo "Driver location: $OUT_DIR/i965_drv_video.so"
echo "To test with vainfo:"
echo "  LIBVA_DRIVER_NAME=i965 LIBVA_DRIVERS_PATH=$OUT_DIR vainfo"
