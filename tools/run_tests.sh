#!/bin/bash
# Every Swift suite. Each is a main file plus the sources it needs.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/leadsniper-tests"
rm -rf "$OUT"; mkdir -p "$OUT"
FAILED=0

ENGINE=(Build Secret RedditGate Feed HackerNews Discover Sectors Scout Share Webhook Score Workspace Draft Radar Updates Watch Strings Fixtures)

run_suite () {
  local name="$1"; shift
  local dir="$OUT/$name"; mkdir -p "$dir"
  for f in "$@"; do cp "$ROOT/macapp/$f.swift" "$dir/"; done
  cp "$ROOT/macapp/$name.swift" "$dir/main.swift"
  local errors
  errors=$(swiftc -O -o "$dir/run" "$dir"/*.swift 2>&1 | grep "error:" | head -3)
  if [ -n "$errors" ]; then
    echo "  ✗ $name did not compile:"; echo "$errors" | sed 's/^/      /'
    FAILED=1; return
  fi
  local result
  result=$("$dir/run" 2>&1)
  if [ $? -eq 0 ]; then
    echo "  ✓ $(echo "$result" | tail -1)"
  else
    echo "$result" | grep -E "❌|FAILURE" | head -12
    echo "  ✗ $name FAILED"
    FAILED=1
  fi
}

run_suite engine_tests "${ENGINE[@]}"

if [ "$FAILED" -eq 0 ]; then echo "All Swift suites passed."; else echo "SWIFT SUITES FAILED"; exit 1; fi
