#!/usr/bin/env bash
# PX4's QNX resource manager serves live state at /dev/px4/state:
# plain `cat` works, values change over time, the device is read-only, and
# the resmgr thread stays below the control loops even for a real-time reader.
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

# The channel is fixed-priority: the server thread must not inherit a
# real-time reader's priority. Read once at FIFO 200 and check.
prio_of() { vm "pidin -p px4 -F '%h|%p'" | awk -F'|' '$1 ~ /qnx_state_resm/ {p=$2; gsub(/[^0-9]/,"",p); print p}'; }
prio="$(prio_of)"
[ -n "$prio" ] || fail "resmgr thread not found"
hi="$(vm "on -p 200f sh -c 'cat /dev/px4/state > /dev/null; pidin -p px4 -F %h\|%p'" | awk -F'|' '$1 ~ /qnx_state_resm/ {p=$2; gsub(/[^0-9]/,"",p); print p}')"
[ -n "$hi" ] || fail "resmgr thread not found after high-priority read"
[ "$prio" -lt 200 ] || fail "resmgr thread priority $prio is too high"
[ "$hi" -lt 200 ] || fail "resmgr thread went to priority $hi after a FIFO-200 reader (priority inheritance not disabled)"

pass "/dev/px4/state readable with cat, live (t advanced $(( (tb - ta) / 1000 )) ms), read-only, thread prio $prio (still $hi after a FIFO-200 reader)"
