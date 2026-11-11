#!/usr/bin/env bash
# Same experiment as run_timing_qnx.sh on Linux SITL, same host: build
# px4_sitl_nolockstep (real-time SIH, like the QNX board) with patch 0004.
#
# PX4 runs as a normal user. Without CAP_SYS_NICE its SCHED_FIFO requests
# fail with EPERM and PX4 falls back to default scheduling (tasks.cpp).
# That is the stock Linux SITL setup; Linux with real-time priorities needs
# root and is not measured here.
#
# Usage: run_timing_linux.sh [label]
#   HOG_THREADS (default 2x host CPUs)
set -euo pipefail
source "$(dirname "$0")/common.sh"

LABEL="${1:-linux}"
HOG_THREADS="${HOG_THREADS:-$(( $(nproc) * 2 ))}"
BUILD="$WORK_DIR/PX4-Autopilot/build/px4_sitl_nolockstep"
ROOTFS="$BUILD/rootfs"

[ -x "$BUILD/bin/px4" ] || { echo "build first: make px4_sitl_nolockstep" >&2; exit 1; }
if pgrep -x px4 >/dev/null; then echo "a px4 is already running on the host; stop it first" >&2; exit 1; fi
gcc -O2 -pthread -o "$WORK_DIR/hog-linux" "$BENCH_DIR/hog.c"

px4cmd() { (cd "$ROOTFS" && "../bin/px4-$1" "${@:2}"); }
measure() {
    px4cmd perf reset >/dev/null
    sleep "$PHASE_S"
    px4cmd perf | perf_to_json "$1"
}

mkdir -p "$ROOTFS"
rm -rf "$ROOTFS"/parameters*.bson "$ROOTFS"/dataman
(cd "$ROOTFS" && PX4_SIM_MODEL=sihsim_quadx PX4_SIMULATOR=sihsim nohup ../bin/px4 -d > "$WORK_DIR/linux-bench.log" 2>&1 &)
trap 'px4cmd shutdown >/dev/null 2>&1 || true; pkill -f "$WORK_DIR/hog-linux" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do px4cmd commander status >/dev/null 2>&1 && break; sleep 1; done
sleep 15

out="$RESULTS/$LABEL.jsonl"
: > "$out"
log "idle ${PHASE_S} s"
measure "$LABEL idle" | tee -a "$out"

log "hog: $HOG_THREADS busy threads, default scheduling, for ${PHASE_S} s"
"$WORK_DIR/hog-linux" "$HOG_THREADS" $((PHASE_S + 20)) &
sleep 3
measure "$LABEL hog ${HOG_THREADS}x" | tee -a "$out"
pid="$(pgrep -f 'bin/px4 -d' | head -1 || true)"
if [ -n "$pid" ]; then
    # per-thread scheduling class and RT priority, as evidence for the writeup
    ps -L -o tid,cls,rtprio,comm -p "$pid" > "$RESULTS/$LABEL-sched.txt"
    log "PX4 thread scheduling classes: $(awk 'NR>1 {print $2}' "$RESULTS/$LABEL-sched.txt" | sort | uniq -c | tr '\n' ' ') (saved $RESULTS/$LABEL-sched.txt)"
fi
log "results in $out"
