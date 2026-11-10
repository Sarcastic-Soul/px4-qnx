# Shared helpers for the host-side QNX tests. Source, don't run.
# shellcheck shell=bash

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SCRIPTS="$REPO_DIR/scripts"
PX4_ROOT="${PX4_ROOT:-/data/px4}"

vm() { timeout "${VM_TIMEOUT:-60}" "$SCRIPTS/vm-ssh.sh" "$@"; }
px4cmd() { "$SCRIPTS/px4-vm.sh" cmd "$@"; }

pass() { echo "[$(basename "$0")] PASS: $*"; }
fail() { echo "[$(basename "$0")] FAIL: $*" >&2; exit 1; }
info() { echo "[$(basename "$0")] $*"; }

ensure_px4() {
    "$SCRIPTS/px4-vm.sh" status || "$SCRIPTS/px4-vm.sh" start "$@" >/dev/null
    # give estimator and modules time to settle
    sleep "${PX4_SETTLE_S:-10}"
}
