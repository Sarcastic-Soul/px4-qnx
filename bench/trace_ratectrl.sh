#!/usr/bin/env bash
# Capture a QNX kernel trace (tracelogger) while PX4 runs, with and without
# a CPU hog, and measure from the trace how long the rate-controller work
# queue thread (wq:rate_ctrl) waits between becoming READY and RUNNING.
#
# This is scheduler-level evidence, independent of PX4's own perf counters.
# Output: bench/results/trace-<phase>.json, raw .kev files in ../work/trace/
#
# Usage: trace_ratectrl.sh   (TRACE_S default 2, HOG_THREADS 8, HOG_PRIO 10)
set -euo pipefail
source "$(dirname "$0")/common.sh"

TRACE_S="${TRACE_S:-2}"
HOG_THREADS="${HOG_THREADS:-8}"
HOG_PRIO="${HOG_PRIO:-10}"
PX4_ROOT="${PX4_ROOT:-/data/px4}"
QNX_SDP="${QNX_SDP:-$HOME/qnx800}"
TRACE_DIR="$WORK_DIR/trace"
vm() { timeout "${VM_TIMEOUT:-90}" "$SCRIPTS/vm-ssh.sh" "$@"; }
mkdir -p "$TRACE_DIR"

export TMPDIR="${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}"
mkdir -p "$TMPDIR"
bash -c "source '$QNX_SDP/qnxsdp-env.sh' >/dev/null; qcc -Vgcc_ntox86_64 -O2 -o '$TMPDIR/hog' '$BENCH_DIR/hog.c'"
vm "slay -f -Q hog tracelogger 2>/dev/null; mkdir -p $PX4_ROOT/bench && rm -f $PX4_ROOT/bench/hog && cat > $PX4_ROOT/bench/hog && chmod +x $PX4_ROOT/bench/hog" < "$TMPDIR/hog"

"$SCRIPTS/px4-vm.sh" status || "$SCRIPTS/px4-vm.sh" start >/dev/null
sleep 5
pid="$(vm "pidin -p px4 -F '%a'" | tail -n +2 | head -1 | tr -d ' ')"
tid="$(vm "pidin -p px4 -F '%b|%h'" | awk -F'|' '$2 ~ /wq:rate_ctrl/ {gsub(/ /,"",$1); print $1}')"
[ -n "$pid" ] && [ -n "$tid" ] || { echo "px4 / wq:rate_ctrl not found" >&2; exit 1; }
log "px4 pid $pid, wq:rate_ctrl tid $tid"

# -F1 -F2 -F6: drop kernel-call, interrupt and communication classes so the
# buffers hold thread state changes only. tracelogger runs above the hog.
capture() { # name hog(0/1)
    local hogcmd=""
    [ "$2" = 1 ] && hogcmd="on -p $HOG_PRIO $PX4_ROOT/bench/hog $HOG_THREADS $((TRACE_S + 4)) > /dev/null & sleep 1;"
    vm "rm -f $PX4_ROOT/trace-$1.kev; $hogcmd on -p 252f tracelogger -s $TRACE_S -n 0 -F1 -F2 -F6 -f $PX4_ROOT/trace-$1.kev > /dev/null 2>&1; wait"
    vm "cat $PX4_ROOT/trace-$1.kev" > "$TRACE_DIR/trace-$1.kev"
    bash -c "source '$QNX_SDP/qnxsdp-env.sh' >/dev/null; traceprinter -f '$TRACE_DIR/trace-$1.kev'" > "$TRACE_DIR/trace-$1.txt"
    "$PY" "$BENCH_DIR/trace_latency.py" "$TRACE_DIR/trace-$1.txt" "$pid" "$tid" --label "$1" | tee "$RESULTS/trace-$1.json"
}

log "trace idle (${TRACE_S} s)"
capture idle 0
log "trace with $HOG_THREADS hog threads at priority $HOG_PRIO (${TRACE_S} s)"
capture hog 1
