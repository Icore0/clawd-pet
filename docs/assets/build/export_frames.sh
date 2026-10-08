#!/bin/sh
# Compiles ExportFrames.swift against the app's sprite code (reads app/Sources, never writes there).
# Prints the path of a work dir containing the binary and frames.json.
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="${TMPDIR:-/tmp}/wigglet-export"
mkdir -p "$OUT"
set --
for f in "$ROOT"/app/Sources/*.swift; do [ "$(basename "$f")" = main.swift ] || set -- "$@" "$f"; done
swiftc -O -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos13.0" "$@" "$ROOT/docs/assets/build/ExportFrames.swift" -o "$OUT/export-frames" 2>/dev/null
HOME="$OUT/home" "$OUT/export-frames" cells > "$OUT/frames.json"
HOME="$OUT/home" "$OUT/export-frames" catalog > "$OUT/catalog.md"
echo "$OUT"
