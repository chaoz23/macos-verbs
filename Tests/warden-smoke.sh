#!/bin/bash
# Smoke test for the warden mediation spine (Warden epic G0/G1).
# Drives the MCP stdio server through one JSON-RPC session and asserts that
# mediation works and a hash-chained provenance record is written.
set -u

warden="${1:-.build/debug/warden}"
verbs="${2:-.build/debug/verbs}"

# Isolate the provenance log to a temp dir so we never touch ~/.warden.
wdir="$(mktemp -d)"
trap 'rm -rf "$wdir"' EXIT
out="$(mktemp)"

session='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"smoke","version":"1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"app_list","arguments":{}}}'

# Export so the vars reach `warden` (the consumer side of the pipe), not printf.
export WARDEN_DIR="$wdir" WARDEN_VERBS_BIN="$verbs"
printf '%s\n' "$session" | "$warden" serve >"$out" 2>/dev/null

fail() { echo "warden smoke: $1" >&2; echo "--- server output ---" >&2; cat "$out" >&2; exit 1; }

grep -q '"serverInfo"' "$out"            || fail "initialize did not return serverInfo"
grep -q '"name":"app_list"' "$out"       || fail "tools/list did not advertise app_list"
grep -q '"isError":false' "$out"         || fail "app_list call did not succeed"
grep -q '"structuredContent"' "$out"     || fail "call result lacked structuredContent"

log="$wdir/provenance.jsonl"
[[ -s "$log" ]]                          || fail "no provenance log was written"
grep -q '"tool":"app_list"' "$log"       || fail "provenance did not record the app_list call"
grep -q '"mutation_class":"read"' "$log" || fail "provenance did not classify the mutation"
grep -q '"prev_hash":"genesis"' "$log"   || fail "provenance chain did not start at genesis"
grep -q '"hash":' "$log"                 || fail "provenance record was not hashed"

echo "warden smoke passed"
