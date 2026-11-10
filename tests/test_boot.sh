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

missing=()
for m in "${modules[@]}"; do
    out="$(px4cmd "$m" status 2>&1 || true)"
    if echo "$out" | grep -qiE "not running|PX4 server not running|cannot execute|not found"; then
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
