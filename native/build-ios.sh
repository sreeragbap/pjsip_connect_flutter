#!/usr/bin/env bash
#
# Builds PJSIP static libs for iOS (device arm64 + simulator arm64/x86_64) and
# assembles pjsip.xcframework for the plugin to vendor.
#
# Prereqs: Xcode + command line tools; network access. Run on macOS.
# Usage:   ./build-ios.sh
#
# Output:  ../ios/sip_connect_flutter/pjsip.xcframework
#          (+ ../ios/sip_connect_flutter/pjsip-headers/ umbrella copy)
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PJ_VERSION="2.15.1"
SSL_VERSION="3.3.2"
MIN="14.0"
WORK="$HERE/.work-ios"
SRC="$WORK/pjproject-$PJ_VERSION"
SSL_SRC="$WORK/openssl-$SSL_VERSION"
OUT="$HERE/../ios/sip_connect_flutter/pjsip.xcframework"

DEV_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

mkdir -p "$WORK"
if [ ! -d "$SRC" ]; then
  echo "==> Fetching pjproject $PJ_VERSION"
  curl -fsSL "https://github.com/pjsip/pjproject/archive/refs/tags/$PJ_VERSION.tar.gz" \
    | tar -xz -C "$WORK"
fi
if [ ! -d "$SSL_SRC" ]; then
  echo "==> Fetching OpenSSL $SSL_VERSION"
  curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-$SSL_VERSION/openssl-$SSL_VERSION.tar.gz" \
    | tar -xz -C "$WORK"
fi
cp "$HERE/config_site.h" "$SRC/pjlib/include/pj/config_site.h"
"$HERE/apply-patches.sh" "$SRC"

# Static OpenSSL per slice (for PJSIP TLS transport + DTLS-SRTP).
# $1=openssl-target  $2=slice-tag  $3=min-version-flag
build_openssl () {
  local TARGET="$1" TAG="$2" MINFLAG="$3" PREFIX="$WORK/ssl-$2"
  [ -f "$PREFIX/lib/libssl.a" ] && { echo "==> OpenSSL for $TAG already built" >&2; return; }
  echo "==> Building OpenSSL $SSL_VERSION for $TAG" >&2
  ( cd "$SSL_SRC"
    make distclean >/dev/null 2>&1 || true
    ./Configure "$TARGET" "$MINFLAG" \
      no-shared no-tests no-apps no-docs --prefix="$PREFIX" --libdir=lib >/dev/null
    make -j8 build_libs >/dev/null
    make install_dev >/dev/null
  ) >&2
}

# Build one slice and return the path to a single merged static lib for it.
# $1=arch  $2=sdkpath  $3=min-version-flag  $4=ssl-slice-tag
build_slice () {
  local ARCH_NAME="$1" SDKPATH="$2" MINFLAG="$3" SSL_TAG="$4" TAG="$1"
  echo "==> Building iOS slice $TAG ($SDKPATH)" >&2
  ( cd "$SRC"
    # Stale/truncated .depend files break make at parse time — always start clean.
    find . -name '.*.depend' -delete
    make distclean >/dev/null 2>&1 || true
    # --disable-*: keep configure from autodetecting host (homebrew) libraries
    # that we don't cross-compile (opus/vpx/sdl/ffmpeg/openh264). SSL comes
    # from our per-slice static OpenSSL build.
    ARCH="-arch $ARCH_NAME" IPHONESDK="$SDKPATH" MIN_IOS="$MINFLAG" \
      ./configure-iphone \
        --with-ssl="$WORK/ssl-$SSL_TAG" \
        --disable-opus --disable-vpx --disable-sdl \
        --disable-ffmpeg --disable-openh264 --disable-opencore-amr
    make dep && make clean && make
  ) >&2
  # Merge every produced module archive for this slice into one lib,
  # together with the slice's OpenSSL (podspec links one library only).
  local MERGED="$WORK/libpjsip-$TAG-$RANDOM.a"
  # shellcheck disable=SC2046
  libtool -static -o "$MERGED" $(find "$SRC" -name '*.a' -path '*/lib/*') \
    "$WORK/ssl-$SSL_TAG/lib/libssl.a" "$WORK/ssl-$SSL_TAG/lib/libcrypto.a"
  echo "$MERGED"
}

build_openssl ios64-xcrun              dev    "-miphoneos-version-min=$MIN"
build_openssl iossimulator-arm64-xcrun simarm "-mios-simulator-version-min=$MIN"
build_openssl iossimulator-x86_64-xcrun simx86 "-mios-simulator-version-min=$MIN"

DEV_A="$(build_slice arm64  "$DEV_SDK" "-miphoneos-version-min=$MIN" dev)"
# Simulator slices use the simulator SDK + the simulator min-version flag.
SIM_ARM_A="$(build_slice arm64  "$SIM_SDK" "-mios-simulator-version-min=$MIN" simarm)"
SIM_X86_A="$(build_slice x86_64 "$SIM_SDK" "-mios-simulator-version-min=$MIN" simx86)"

# CocoaPods requires every slice's library to share one binary name.
DEV_DIR="$WORK/dev"; SIM_DIR="$WORK/sim"
rm -rf "$DEV_DIR" "$SIM_DIR"; mkdir -p "$DEV_DIR" "$SIM_DIR"
cp "$DEV_A" "$DEV_DIR/libpjsip.a"
lipo -create "$SIM_ARM_A" "$SIM_X86_A" -output "$SIM_DIR/libpjsip.a"
DEV_A="$DEV_DIR/libpjsip.a"
SIM_A="$SIM_DIR/libpjsip.a"

# Collect PJSIP public headers (pjsua2 headers live under pjsip/include).
HEADERS="$WORK/headers"
rm -rf "$HEADERS"; mkdir -p "$HEADERS"
for m in pjlib pjlib-util pjnath pjmedia pjsip; do
  cp -R "$SRC/$m/include/." "$HEADERS/" 2>/dev/null || true
done
# Keep a copy next to the framework for the Swift/ObjC++ bridge to import.
rm -rf "$HERE/../ios/sip_connect_flutter/pjsip-headers"
cp -R "$HEADERS" "$HERE/../ios/sip_connect_flutter/pjsip-headers"

rm -rf "$OUT"
xcodebuild -create-xcframework \
  -library "$DEV_A" -headers "$HEADERS" \
  -library "$SIM_A" -headers "$HEADERS" \
  -output "$OUT"

echo "==> Done. $OUT  (headers also copied to ios/pjsip-headers/)"
