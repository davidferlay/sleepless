#!/bin/sh
# Static checks: Swift formatting, Info.plist, shell scripts, workflows.
# shellcheck and actionlint are optional locally and required in CI (CI=true).
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

status=0

run() {
    echo "==> $*"
    if ! "$@"; then
        status=1
    fi
}

optional_tool() {
    tool=$1
    shift
    if command -v "$tool" >/dev/null 2>&1; then
        run "$tool" "$@"
    elif [ "${CI:-}" = true ]; then
        echo "error: $tool is required in CI" >&2
        status=1
    else
        echo "==> $tool not installed, skipped (install with: brew install $tool)"
    fi
}

run /usr/bin/swift format lint --strict --recursive Package.swift Sources Tests Scripts/make-icon.swift
run /usr/bin/plutil -lint Resources/Info.plist
optional_tool shellcheck Scripts/*.sh .githooks/pre-commit
optional_tool actionlint

exit "$status"
