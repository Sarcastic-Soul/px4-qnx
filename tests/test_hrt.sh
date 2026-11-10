#!/usr/bin/env bash
# PX4's high-resolution timer (hrt_absolute_time, microseconds) tracks QNX
# CLOCK_MONOTONIC: over ~10 s the two deltas agree within 1 ms, and PX4
# timestamps never step backwards.
#
# PX4 time is read from `listener sensor_gyro`, which prints a message
# timestamp plus "(X seconds ago)"; their sum is PX4's clock at print time.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

QNX_SDP="${QNX_SDP:-$HOME/qnx800}"
export TMPDIR="${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}"
mkdir -p "$TMPDIR"
helper="$TMPDIR/monotime"
bash -c "source '$QNX_SDP/qnxsdp-env.sh' >/dev/null; qcc -Vgcc_ntox86_64 -O2 -o '$helper' '$TESTS_DIR/helpers/monotime.c'"
vm "mkdir -p $PX4_ROOT/tests" 
vm "cat > $PX4_ROOT/tests/monotime && chmod +x $PX4_ROOT/tests/monotime" < "$helper"

ensure_px4

# One sample: "<px4_now_us> <monotonic_us>" taken in the same VM shell.
sample() {
    vm "cd $PX4_ROOT/rootfs && ../bin/px4-listener sensor_gyro -n 1 && $PX4_ROOT/tests/monotime" |
        awk '/^ *timestamp:/ && !t { ts=$2; ago=$3; gsub(/[()]/,"",ago); t=1 }
             /^[0-9]+$/ { mono=$1 }
             END { if (t && mono) printf "%.0f %s\n", ts + ago*1e6, mono }'
}

read -r p0 m0 < <(sample)
[ -n "${p0:-}" ] && [ -n "${m0:-}" ] || fail "could not read timestamps"
prev=$p0
backwards=0
for _ in $(seq 1 10); do
    sleep 1
    read -r p m < <(sample)
    [ "$p" -ge "$prev" ] || backwards=$((backwards + 1))
    prev=$p
done
read -r p1 m1 <<<"$p $m"

dp=$((p1 - p0))
dm=$((m1 - m0))
drift=$((dp - dm)); drift=${drift#-}
info "PX4 delta ${dp} us, CLOCK_MONOTONIC delta ${dm} us, difference ${drift} us"

[ "$backwards" -eq 0 ] || fail "PX4 time stepped backwards $backwards times"
[ "$dm" -gt 9000000 ] || fail "test window too short (${dm} us)"
[ "$drift" -lt 1000 ] || fail "drift ${drift} us >= 1 ms"
pass "hrt monotonic over 11 samples, drift ${drift} us over $((dm / 1000)) ms"
