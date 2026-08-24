#!/bin/bash
# The whole thing, in the order that cannot produce a half-release.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "── tests ─────────────────────────────────────────"
"$ROOT/tools/run_tests.sh"
echo
echo "── app ───────────────────────────────────────────"
python3 "$ROOT/tools/build_desktop.py"
echo "── site ──────────────────────────────────────────"
python3 "$ROOT/tools/build_site.py"
echo
echo "Ready to publish: $ROOT/site"
