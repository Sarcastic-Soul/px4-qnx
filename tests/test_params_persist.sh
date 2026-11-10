#!/usr/bin/env bash
# A parameter set on QNX survives a PX4 restart (params stored in
# /data/px4/rootfs/parameters.bson on the writable data partition).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PARAM="${PARAM:-MPC_XY_CRUISE}"
VALUE="${VALUE:-7.25}"

ensure_px4
orig="$(px4cmd param show -q "$PARAM" | tr -d '\r')"
info "$PARAM was $orig, setting $VALUE"
px4cmd param set "$PARAM" "$VALUE" >/dev/null
# PX4 auto-saves params with a short delay; force the write before stopping.
px4cmd param save >/dev/null

"$SCRIPTS/px4-vm.sh" stop >/dev/null
"$SCRIPTS/px4-vm.sh" start >/dev/null
got="$(px4cmd param show -q "$PARAM" | tr -d '\r')"

# restore before asserting so a failure does not leave the vehicle changed
px4cmd param set "$PARAM" "$orig" >/dev/null
px4cmd param save >/dev/null

awk -v a="$got" -v b="$VALUE" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d < 1e-4)}' ||
    fail "$PARAM after restart is '$got', expected $VALUE"
pass "$PARAM kept value $got across restart"
