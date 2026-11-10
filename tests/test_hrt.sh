#!/usr/bin/env bash
# PX4's high-resolution timer (hrt_absolute_time, microseconds) tracks QNX
# CLOCK_MONOTONIC: over ~12 s the offset between them changes by < 1 ms, and
# PX4 timestamps never step backwards.
#
# PX4 time comes from /dev/px4/state (t_us = hrt_absolute_time() at open()).
# tests/helpers/hrtcheck.c brackets each read with CLOCK_MONOTONIC, so the
# offset is known to within the read's round trip (tens of microseconds).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

QNX_SDP="${QNX_SDP:-$HOME/qnx800}"
SAMPLES="${SAMPLES:-25}"
INTERVAL_MS="${INTERVAL_MS:-500}"
export TMPDIR="${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}"
mkdir -p "$TMPDIR"
helper="$TMPDIR/hrtcheck"
bash -c "source '$QNX_SDP/qnxsdp-env.sh' >/dev/null; qcc -Vgcc_ntox86_64 -O2 -o '$helper' '$TESTS_DIR/helpers/hrtcheck.c'"
vm "mkdir -p $PX4_ROOT/tests && rm -f $PX4_ROOT/tests/hrtcheck && cat > $PX4_ROOT/tests/hrtcheck && chmod +x $PX4_ROOT/tests/hrtcheck" < "$helper"

ensure_px4

data="$(VM_TIMEOUT=120 vm "$PX4_ROOT/tests/hrtcheck $SAMPLES $INTERVAL_MS")"
[ "$(echo "$data" | wc -l)" -eq "$SAMPLES" ] || fail "expected $SAMPLES samples, got: $data"

# per sample: midpoint offset and bracket width; check px4 time strictly increases
read -r first_mid last_mid max_width backwards window < <(echo "$data" | awk '
    { b=$1; t=$2; a=$3; mid = (b + a) / 2 - t; w = a - b
      if (NR == 1) { first = mid; b0 = b }
      if (NR > 1 && t <= prev) back++
      if (w > maxw) maxw = w
      prev = t; last = mid; bl = b }
    END { printf "%.0f %.0f %d %d %d\n", first, last, maxw, back + 0, bl - b0 }')

drift=$((last_mid - first_mid)); drift=${drift#-}
info "offset (monotonic - px4) start ${first_mid} us, end ${last_mid} us, worst read bracket ${max_width} us, window $((window / 1000)) ms"

[ "$backwards" -eq 0 ] || fail "PX4 time did not increase $backwards times"
[ "$window" -gt 9000000 ] || fail "test window too short (${window} us)"
[ "$max_width" -lt 1000 ] || fail "read bracket ${max_width} us too wide to judge 1 ms drift"
[ "$drift" -lt 1000 ] || fail "drift ${drift} us >= 1 ms"
pass "hrt monotonic over $SAMPLES samples, drift ${drift} us over $((window / 1000)) ms (bracket <= ${max_width} us)"
