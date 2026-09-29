#!/usr/bin/env bash
# Static checks that need no Godot executable at run time:
#   * gdparse / gdlint  (pip install gdtoolkit)  - syntax and style
#   * gdcheck.py                                 - names, members, signals, arities against the
#                                                  engine API (needs an extension_api.json)
#   * the Python reference simulation and its golden test vectors
#   * gdemu: every test suite executed on an emulator of the GDScript logic (tools/gdemu/README.md);
#     set SMOKE=1 to add a short whole-app monkey run on engine stubs
#
#   tools/check_static.sh [path/to/extension_api.json]
#
# Produce extension_api.json once with:  godot --headless --dump-extension-api
set -uo pipefail
cd "$(dirname "$0")/.."
API="${1:-extension_api.json}"
FAIL=0

echo "== gdparse"
gdparse $(find src tests -name '*.gd') || FAIL=1
echo "== gdlint"
gdlint src tests || FAIL=1
if [ -f "$API" ]; then
  echo "== gdcheck ($API)"
  python3 tools/gdcheck.py --api "$API" --project . src tests || FAIL=1
else
  echo "== gdcheck skipped (no $API; see the header of this script)"
fi
echo "== golden vectors are up to date"
python3 tools/reference/gen_golden.py > /dev/null && git diff --quiet -- tests/golden || { echo "golden vectors changed - review and commit them"; FAIL=1; }
echo "== gdemu (tests on the GDScript emulator, no engine)"
python3 -m tools.gdemu test || FAIL=1
if [ "${SMOKE:-0}" = "1" ]; then
  echo "== gdemu smoke (monkey run on engine stubs)"
  python3 -m tools.gdemu smoke --seeded --actions 200 --seed 1 || FAIL=1
fi
exit $FAIL
