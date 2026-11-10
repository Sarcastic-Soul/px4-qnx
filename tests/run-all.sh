#!/usr/bin/env bash
# Run every QNX test against the running VM. Starts PX4 fresh first.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$DIR/../scripts"
PY="${PYTHON:-$DIR/../../work/venv/bin/python}"

"$SCRIPTS/px4-vm.sh" stop >/dev/null
"$SCRIPTS/px4-vm.sh" start --clean || exit 1

failed=()
for t in test_boot.sh test_priorities.sh test_hrt.sh test_params_persist.sh test_resmgr.sh test_fault_isolation.sh; do
    "$DIR/$t" || failed+=("$t")
done
timeout 600 "$PY" "$DIR/test_flight.py" || failed+=("test_flight.py")

if [ ${#failed[@]} -gt 0 ]; then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "ALL TESTS PASSED"
