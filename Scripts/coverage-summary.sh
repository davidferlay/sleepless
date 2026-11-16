#!/bin/sh
# Prints line coverage of SleeplessCore from the last `swift test --enable-code-coverage` run and,
# in GitHub Actions, adds it to the job summary.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

BIN_PATH=$(/usr/bin/swift build --show-bin-path)
PROFDATA="$BIN_PATH/codecov/default.profdata"
TEST_BINARY="$BIN_PATH/SleeplessPackageTests.xctest/Contents/MacOS/SleeplessPackageTests"

if [ ! -f "$PROFDATA" ]; then
    echo "error: $PROFDATA not found, run make coverage" >&2
    exit 1
fi

REPORT=$(/usr/bin/xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" Sources/SleeplessCore)
echo "$REPORT"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Unit test coverage (SleeplessCore)"
        echo
        echo '```'
        echo "$REPORT"
        echo '```'
    } >>"$GITHUB_STEP_SUMMARY"
fi
