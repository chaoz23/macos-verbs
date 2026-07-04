#!/bin/bash
set -u

binary="${1:-.build/debug/verbs}"
stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$stdout_file" "$stderr_file"' EXIT

assert_failure() {
    local expected="$1"
    local label="$2"
    shift 2

    "$binary" "$@" >"$stdout_file" 2>"$stderr_file"
    local actual="$?"

    if [[ "$actual" -ne "$expected" ]]; then
        echo "$label: expected exit $expected, got $actual" >&2
        cat "$stderr_file" >&2
        exit 1
    fi
    if [[ -s "$stdout_file" ]]; then
        echo "$label: failure wrote to stdout" >&2
        cat "$stdout_file" >&2
        exit 1
    fi
    if ! grep -q '^Error:' "$stderr_file"; then
        echo "$label: stderr did not contain an error message" >&2
        cat "$stderr_file" >&2
        exit 1
    fi
}

assert_success() {
    local label="$1"
    shift

    "$binary" "$@" >"$stdout_file" 2>"$stderr_file"
    local actual="$?"

    if [[ "$actual" -ne 0 ]]; then
        echo "$label: expected exit 0, got $actual" >&2
        cat "$stderr_file" >&2
        exit 1
    fi
    if [[ ! -s "$stdout_file" || -s "$stderr_file" ]]; then
        echo "$label: unexpected output streams" >&2
        exit 1
    fi
}

assert_success help --help
assert_success version --version
assert_failure 1 actionable open /definitely/not/a/real/macos-verbs-test-file --json
assert_failure 2 system open README.md --with __MACOS_VERBS_MISSING_APP__ --json
assert_failure 64 usage darkmode bananas --json

echo "error contract passed"
