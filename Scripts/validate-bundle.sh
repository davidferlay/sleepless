#!/bin/sh
# Checks that the built app bundle is well formed, signed and universal.
# Usage: Scripts/validate-bundle.sh [path to Sleepless.app]
# Environment: EXPECTED_VERSION (optional), EXPECTED_ARCHS (default "arm64 x86_64").
set -eu

APP=${1:-build/Sleepless.app}
EXPECTED_ARCHS=${EXPECTED_ARCHS:-arm64 x86_64}
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/Sleepless"
failures=0

pass() {
    echo "ok   $1"
}

fail() {
    echo "FAIL $1"
    failures=$((failures + 1))
}

expect_equal() {
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1 (got '$2', expected '$3')"
    fi
}

plist_value() {
    /usr/bin/plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null || echo "<missing>"
}

if [ ! -d "$APP" ]; then
    echo "error: $APP not found, run make app first" >&2
    exit 1
fi

if /usr/bin/plutil -lint "$PLIST" >/dev/null; then pass "Info.plist is valid"; else fail "Info.plist is valid"; fi
expect_equal "bundle identifier" "$(plist_value CFBundleIdentifier)" io.github.davidferlay.Sleepless
expect_equal "executable name" "$(plist_value CFBundleExecutable)" Sleepless
expect_equal "LSUIElement" "$(plist_value LSUIElement)" true
expect_equal "minimum macOS" "$(plist_value LSMinimumSystemVersion)" 13.0
if [ -n "${EXPECTED_VERSION:-}" ]; then
    expect_equal "version" "$(plist_value CFBundleShortVersionString)" "$EXPECTED_VERSION"
fi
case "$(plist_value SleeplessBuildChannel)" in
    release | rc | dev | local) pass "build channel" ;;
    *) fail "build channel" ;;
esac
if /usr/bin/grep -q '__[A-Z_]*__' "$PLIST"; then
    fail "no unsubstituted placeholders"
else
    pass "no unsubstituted placeholders"
fi
expect_equal "PkgInfo" "$(/bin/cat "$APP/Contents/PkgInfo" 2>/dev/null || true)" 'APPL????'
if [ -s "$APP/Contents/Resources/AppIcon.icns" ]; then pass "app icon"; else fail "app icon"; fi

archs=$(/usr/bin/lipo -archs "$BINARY" 2>/dev/null || true)
for arch in $EXPECTED_ARCHS; do
    case " $archs " in
        *" $arch "*) pass "architecture $arch" ;;
        *) fail "architecture $arch (binary has: $archs)" ;;
    esac
done
for arch in $archs; do
    minos=$(/usr/bin/vtool -arch "$arch" -show-build "$BINARY" 2>/dev/null | /usr/bin/awk '/minos/ { print $2 }')
    expect_equal "minimum OS of the $arch slice" "$minos" 13.0
done

if /usr/bin/codesign --verify --strict --verbose=2 "$APP" 2>/dev/null; then
    pass "code signature"
else
    fail "code signature"
fi

non_system=$(/usr/bin/otool -L "$BINARY" | /usr/bin/awk 'NR > 1 && !/:$/ { print $1 }' |
    /usr/bin/grep -v -E '^(/usr/lib/|/System/Library/)' || true)
if [ -z "$non_system" ]; then
    pass "links only system libraries"
else
    fail "links only system libraries (also: $non_system)"
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "All bundle checks passed"
