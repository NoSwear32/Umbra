#!/usr/bin/env bash
# Runs the automated tests headless (needs a Godot 4.3+ executable).
#
#   tools/run_tests.sh                  # uses "godot" from PATH (or $GODOT)
#   tools/run_tests.sh /path/to/godot
#
# Exit code 0 = every test passed and the engine reported no script errors.
# (GDScript keeps running after a runtime error, so the output is scanned for them too.)
set -uo pipefail
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."

echo "== importing project (builds the class cache and imports assets)"
"$GODOT" --headless --path . --import || { echo "import failed"; exit 2; }

echo "== running tests"
LOG="$(mktemp)"
"$GODOT" --headless --path . -s tests/run_tests.gd 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}

if grep -qE "SCRIPT ERROR|Parse Error" "$LOG"; then
  echo ""
  echo "== the engine reported script errors (see above): failing the run"
  STATUS=1
fi
rm -f "$LOG"
exit "$STATUS"
