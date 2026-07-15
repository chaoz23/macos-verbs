#!/bin/bash
# Build and install the macos-verbs binaries (verbs + warden).
#
#   ./install.sh                 # installs to /usr/local/bin (needs write access)
#   PREFIX="$HOME/.local/bin" ./install.sh   # user-local, no sudo
#
# Requires macOS 13+ and Swift 5.9+ (Command Line Tools are enough).
set -euo pipefail

PREFIX="${PREFIX:-/usr/local/bin}"
cd "$(dirname "$0")"

echo "building release binaries…"
swift build -c release

bindir=".build/release"
mkdir -p "$PREFIX"
for b in verbs warden; do
    if [[ ! -x "$bindir/$b" ]]; then echo "missing $bindir/$b — build failed?" >&2; exit 1; fi
    install -m 0755 "$bindir/$b" "$PREFIX/$b"
    echo "installed $PREFIX/$b"
done

echo
echo "done. Verify:  $PREFIX/verbs app frontmost --json"
echo "MCP server:    $PREFIX/warden serve   (point your agent's MCP config here)"
case ":$PATH:" in
    *":$PREFIX:"*) ;;
    *) echo "note: $PREFIX is not on your PATH — add it or use the absolute path." ;;
esac
