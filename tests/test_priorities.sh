#!/usr/bin/env bash
# Every PX4 thread runs at a valid QNX priority (1..253; 254/255 are
# reserved for the clock IST and IPIs), real-time threads use SCHED_FIFO,
# and the rate controller work queue has the highest PX4 priority.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ensure_px4

# pidin prints "<prio><policy>", e.g. "253f" (f = FIFO, r = RR, o = OTHER)
table="$(vm "pidin -p px4 -F '%b|%h|%p'" | tail -n +2)"
[ -n "$table" ] || fail "no px4 threads found"
echo "$table" | sed 's/^/    /'

bad="$(echo "$table" | awk -F'|' '{p=$3; gsub(/[^0-9]/,"",p); p += 0; if (p < 1 || p > 253) print}')"
[ -z "$bad" ] || fail "threads outside 1..253: $bad"

max="$(echo "$table" | awk -F'|' '{p=$3; gsub(/[^0-9]/,"",p); p += 0; if (p > m) m = p} END {print m}')"
rate="$(echo "$table" | awk -F'|' '$2 ~ /wq:rate_ctrl/ {p=$3; gsub(/[^0-9]/,"",p); p += 0; print p}')"
[ -n "$rate" ] || fail "wq:rate_ctrl thread not found"
[ "$rate" = "$max" ] || fail "wq:rate_ctrl at $rate, below PX4 max $max"

# Work queues and PX4 tasks must not silently inherit the shell's priority 10.
for t in wq:rate_ctrl wq:INS0 nav_and_controllers wq:hp_default; do
    pol="$(echo "$table" | awk -F'|' -v t="$t" '$2 ~ t {print $3}' | tr -d ' 0-9')"
    [ "$pol" = "f" ] || fail "$t not SCHED_FIFO (policy '$pol')"
done
ordered="$(echo "$table" | awk -F'|' '
    {p=$3; gsub(/[^0-9]/,"",p); p += 0; n=$2; gsub(/^ +| +$/,"",n); prio[n]=p}
    END {print (prio["wq:rate_ctrl"] > prio["wq:INS0"] && prio["wq:INS0"] > prio["wq:hp_default"] && prio["wq:hp_default"] > prio["wq:lp_default"]) ? "ok" : "bad"}')"
[ "$ordered" = "ok" ] || fail "work queue priorities not ordered rate_ctrl > INS0 > hp_default > lp_default"

pass "all $(echo "$table" | wc -l) threads in 1..253, rate_ctrl at $rate (highest), work queues SCHED_FIFO and ordered"
