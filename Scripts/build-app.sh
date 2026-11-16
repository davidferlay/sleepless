#!/bin/sh
# Builds build/Sleepless.app with SwiftPM and the Command Line Tools (Xcode not required).
#
# Environment (all optional):
#   VERSION       CFBundleShortVersionString, default 0.0.0
#   BUILD_NUMBER  CFBundleVersion, default the commit count
#   CHANNEL       release, rc, dev or local, default local
#   ARCHS         architectures to build, default "arm64 x86_64"
#   OUTPUT_DIR    default build
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

VERSION=${VERSION:-0.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-$(/usr/bin/git rev-list --count HEAD 2>/dev/null || echo 1)}
CHANNEL=${CHANNEL:-local}
COMMIT=$(/usr/bin/git rev-parse --short HEAD 2>/dev/null || echo unknown)
ARCHS=${ARCHS:-arm64 x86_64}
OUTPUT_DIR=${OUTPUT_DIR:-build}
APP="$OUTPUT_DIR/Sleepless.app"

case "$CHANNEL" in
    release | rc | dev | local) ;;
    *)
        echo "error: CHANNEL must be release, rc, dev or local (got '$CHANNEL')" >&2
        exit 1
        ;;
esac

binaries=""
for arch in $ARCHS; do
    echo "==> Building $arch"
    /usr/bin/swift build -c release --product Sleepless --triple "$arch-apple-macosx13.0"
    binaries="$binaries .build/$arch-apple-macosx/release/Sleepless"
done

echo "==> Assembling $APP"
/bin/rm -rf "$APP"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# shellcheck disable=SC2086 # the binary list is split on purpose; the paths contain no spaces
/usr/bin/lipo -create $binaries -output "$APP/Contents/MacOS/Sleepless"
/usr/bin/sed \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
    -e "s/__CHANNEL__/$CHANNEL/g" \
    -e "s/__COMMIT__/$COMMIT/g" \
    Resources/Info.plist >"$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/printf 'APPL????' >"$APP/Contents/PkgInfo"
/bin/cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP ($VERSION, build $BUILD_NUMBER, $CHANNEL $COMMIT, $(/usr/bin/lipo -archs "$APP/Contents/MacOS/Sleepless"))"
