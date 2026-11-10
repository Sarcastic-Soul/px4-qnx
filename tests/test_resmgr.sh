#!/usr/bin/env bash
# PX4's QNX resource manager serves live state at /dev/px4/state:
# plain `cat` works, values change over time, the device is read-only, and
# the resmgr thread runs below every control-loop thread.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ensure_px4

a="$(vm "cat /dev/px4/state")"
sleep 1
b="$(vm "cat /dev/px4/state")"
info "read: $b"

for key in t_us armed nav_state x y alt vx vy vz heading_deg pos_valid battery; do
    echo "$b" | grep -q "\b$key=" || fail "missing field $key"
done
ta="$(echo "$a" | sed -n 's/.*t_us=\([0-9]*\).*/\1/p')"
tb="$(echo "$b" | sed -n 's/.*t_us=\([0-9]*\).*/\1/p')"
[ "$tb" -gt "$ta" ] || fail "timestamp did not advance ($ta -> $tb)"
echo "$b" | grep -q "pos_valid=1" || fail "position not valid"

if vm "echo x > /dev/px4/state" 2>/dev/null; then fail "device accepted a write"; fi

prio="$(vm "pidin -p px4 -F '%h|%p'" | awk -F'|' '$1 ~ /qnx_state_resm/ {p=$2; gsub(/[^0-9]/,"",p); print p}')"
[ -n "$prio" ] || fail "resmgr thread not found"
# QNX message passing: the server thread runs at its client's priority
# (here the prio-10 shell), so readers can never push it above the control loops.
[ "$prio" -lt 200 ] || fail "resmgr thread priority $prio is too high"

pass "/dev/px4/state readable with cat, live (t advanced $(( (tb - ta) / 1000 )) ms), read-only, thread prio $prio"
