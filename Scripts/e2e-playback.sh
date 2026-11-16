#!/bin/sh
# End-to-end: real audio playback makes Sleepless hold its power assertion, and the assertion is
# released after the hold. Exits 0 with a notice when the machine has no default audio output device.
# Usage: Scripts/e2e-playback.sh [path to Sleepless.app]
set -eu

APP=${1:-build/Sleepless.app}
BINARY="$APP/Contents/MacOS/Sleepless"
ASSERTION_NAME="Sleepless: audio playback"
START_DELAY=1
STOP_DELAY=4
TONE_SECONDS=6

notice() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "::notice title=End-to-end playback test::$1"
    else
        echo "$1"
    fi
}

fail() {
    echo "FAIL $1" >&2
    exit 1
}

has_assertion() {
    /usr/bin/pmset -g assertions | /usr/bin/grep -i -F "pid $pid(Sleepless)" |
        /usr/bin/grep -q -F "\"$ASSERTION_NAME\""
}

# shellcheck disable=SC2317 # called indirectly through wait_until
has_no_assertion() {
    ! has_assertion
}

# Runs the command "$2 ..." every 0.5 s for up to $1 seconds until it succeeds.
wait_until() {
    tries=$(($1 * 2))
    shift
    while [ "$tries" -gt 0 ]; do
        if "$@"; then
            return 0
        fi
        sleep 0.5
        tries=$((tries - 1))
    done
    return 1
}

[ -x "$BINARY" ] || fail "$BINARY not found, run make app first"

if ! /usr/sbin/system_profiler SPAudioDataType 2>/dev/null | /usr/bin/grep -q "Default Output Device: Yes"; then
    notice "No default audio output device on this machine, skipping the end-to-end playback test"
    exit 0
fi

WORK_DIR=$(/usr/bin/mktemp -d)
TONE="$WORK_DIR/tone.wav"
/usr/bin/python3 - "$TONE" "$TONE_SECONDS" <<'EOF'
import math
import struct
import sys
import wave

path, seconds = sys.argv[1], int(sys.argv[2])
rate = 44100
frames = b"".join(
    struct.pack("<h", int(1000 * math.sin(2 * math.pi * 440 * i / rate))) for i in range(rate * seconds)
)
with wave.open(path, "wb") as tone:
    tone.setnchannels(1)
    tone.setsampwidth(2)
    tone.setframerate(rate)
    tone.writeframes(frames)
EOF

"$BINARY" -startDelay "$START_DELAY" -stopDelay "$STOP_DELAY" &
pid=$!
player=""
# shellcheck disable=SC2317 # called by the EXIT trap
cleanup() {
    if [ -n "$player" ]; then
        kill "$player" 2>/dev/null || true
    fi
    kill "$pid" 2>/dev/null || true
    /bin/rm -rf "$WORK_DIR"
}
trap cleanup EXIT

sleep $((START_DELAY + 2))
if has_assertion; then
    fail "the assertion is held before the test plays anything: other audio is playing on this Mac, stop it and re-run"
fi
echo "ok   no assertion while nothing plays"

/usr/bin/afplay -v 0.3 "$TONE" &
player=$!
wait_until 5 has_assertion || fail "no assertion within 5 s of playback starting"
echo "ok   assertion held during playback"

wait "$player" || true
player=""
sleep 1
has_assertion || fail "assertion gone less than 1 s after playback stopped (stop delay is $STOP_DELAY s)"
echo "ok   assertion still held right after playback (hold)"

wait_until $((STOP_DELAY + 5)) has_no_assertion || fail "assertion still held $((STOP_DELAY + 5)) s after playback"
echo "ok   assertion released after the hold"

echo "End-to-end playback test passed"
