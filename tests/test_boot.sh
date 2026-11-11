#!/usr/bin/env bash
# PX4 boots on QNX and the modules SIH quad flight needs are running.
# Module list from docs/module-baseline.md.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ensure_px4

modules=(commander navigator dataman ekf2 sensors simulator_sih
         mc_rate_control mc_att_control mc_pos_control control_allocator
         flight_mode_manager land_detector mc_hover_thrust_estimator
         pwm_out_sim mavlink logger load_mon manual_control rc_update
         battery_simulator)

# A running module answers "status" with exit 0 (newer PX4 prints the default
# "running" to PX4's stdout, so the client may see no text);
# a stopped one prints "not running" and exits non-zero.
# mavlink is special: its status printf()s straight to PX4's stdout (not back
# to the client), so check for its threads instead.
missing=()
for m in "${modules[@]}"; do
    if [ "$m" = mavlink ]; then
        n="$(vm "pidin -p px4 -F '%b %h'" | grep -c 'mavlink_if' || true)"
        [ "$n" -ge 2 ] || missing+=("$m")
        continue
    fi
    if ! out="$(px4cmd "$m" status 2>&1)" || echo "$out" | grep -qiE "not running|cannot execute"; then
        missing+=("$m")
    fi
done
[ ${#missing[@]} -eq 0 ] || fail "modules not running: ${missing[*]}"

# Control loops actually run: rate controller and EKF2 on their work queues.
wq="$(px4cmd work_queue status 2>&1)"
for item in mc_rate_control ekf2 mc_att_control; do
    rate="$(echo "$wq" | grep -E "\) $item " | awk '{for(i=1;i<=NF;i++) if($i=="Hz") print $(i-1)}' | head -1)"
    [ -n "$rate" ] || fail "$item not on a work queue"
    awk -v r="$rate" 'BEGIN{exit !(r > 100)}' || fail "$item running at $rate Hz (< 100 Hz)"
    info "$item at $rate Hz"
done

ver="$(px4cmd ver all 2>&1)"
echo "$ver" | grep -q "OS: QNX" || fail "ver does not report OS QNX"

pass "${#modules[@]} modules running, control loops active, OS reported as QNX"
