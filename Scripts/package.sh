#!/bin/sh
# Packages build/Sleepless.app into Sleepless-<version>.dmg, Sleepless-<version>.zip and SHA256SUMS.txt.
# Usage: Scripts/package.sh <version>
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

VERSION=${1:?usage: Scripts/package.sh <version>}
OUTPUT_DIR=${OUTPUT_DIR:-build}
APP="$OUTPUT_DIR/Sleepless.app"
DMG="$OUTPUT_DIR/Sleepless-$VERSION.dmg"
ZIP="$OUTPUT_DIR/Sleepless-$VERSION.zip"
STAGING="$OUTPUT_DIR/dmg-staging"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found, run make app first" >&2
    exit 1
fi

/bin/rm -rf "$STAGING" "$DMG" "$ZIP" "$OUTPUT_DIR/SHA256SUMS.txt"
/bin/mkdir -p "$STAGING"
/usr/bin/ditto "$APP" "$STAGING/Sleepless.app"
/bin/ln -s /Applications "$STAGING/Applications"

# hdiutil occasionally fails with "Resource busy" on CI runners; retry a few times.
attempt=1
until /usr/bin/hdiutil create -volname "Sleepless $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"; do
    if [ "$attempt" -ge 3 ]; then
        echo "error: hdiutil failed $attempt times" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    echo "hdiutil failed, retrying ($attempt/3)"
    sleep 5
done
/bin/rm -rf "$STAGING"

/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUTPUT_DIR" && /usr/bin/shasum -a 256 "Sleepless-$VERSION.dmg" "Sleepless-$VERSION.zip" >SHA256SUMS.txt)
/bin/cat "$OUTPUT_DIR/SHA256SUMS.txt"
