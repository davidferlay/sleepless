#!/bin/sh
# Smoke test: the app starts, stays up, logs its start, and quits cleanly on SIGTERM.
# Usage: Scripts/smoke-test.sh [path to Sleepless.app]
set -eu

APP=${1:-build/Sleepless.app}
BINARY="$APP/Contents/MacOS/Sleepless"
SUBSYSTEM=io.github.davidferlay.Sleepless

fail() {
    echo "FAIL $1" >&2
    exit 1
}

# True while the process exists and is not a zombie.
is_running() {
    state=$(/bin/ps -p "$1" -o stat= 2>/dev/null || true)
    [ -n "$state" ] && [ "${state#Z}" = "$state" ]
}

# Waits up to $1 seconds for a log message of this run that contains $2.
wait_for_log() {
    remaining=$1
    while [ "$remaining" -gt 0 ]; do
        if /usr/bin/log show --style compact --start "$START" \
            --predicate "subsystem == \"$SUBSYSTEM\" AND processIdentifier == $pid" 2>/dev/null |
            /usr/bin/grep -q -F "$2"; then
            return 0
        fi
        sleep 1
        remaining=$((remaining - 1))
    done
    return 1
}

[ -x "$BINARY" ] || fail "$BINARY not found, run make app first"

START=$(/bin/date '+%Y-%m-%d %H:%M:%S')
"$BINARY" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT

sleep 5
is_running "$pid" || fail "the app exited within 5 s of launch"
echo "ok   still running after 5 s (pid $pid)"

wait_for_log 10 "Sleepless started" || fail "'Sleepless started' was not logged"
echo "ok   start logged"

kill -TERM "$pid"
waited=0
while is_running "$pid"; do
    [ "$waited" -lt 5 ] || fail "still running 5 s after SIGTERM"
    sleep 1
    waited=$((waited + 1))
done
status=0
wait "$pid" || status=$?
[ "$status" -eq 0 ] || fail "exit status $status after SIGTERM"
echo "ok   exited with status 0 after SIGTERM"

wait_for_log 10 "Sleepless stopped" || fail "'Sleepless stopped' was not logged"
echo "ok   stop logged"

crash=$(/usr/bin/find "$HOME/Library/Logs/DiagnosticReports" -name 'Sleepless*' -newer "$APP/Contents/Info.plist" \
    2>/dev/null | /usr/bin/head -1)
[ -z "$crash" ] || fail "crash report found: $crash"
echo "ok   no crash report"

trap - EXIT
echo "Smoke test passed"
