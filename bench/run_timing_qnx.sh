#!/usr/bin/env bash
# Rate-controller loop timing on QNX, idle vs. CPU hog.
#
# Phase 1: PHASE_S seconds idle. Phase 2: PHASE_S seconds with HOG_THREADS
# busy threads at QNX priority HOG_PRIO (default 10 = normal user priority,
# below every PX4 real-time thread). Result: bench/results/<label>.jsonl
#
# Usage: run_timing_qnx.sh [label]
#   HOG_THREADS (default 8 = 2x the VM's 4 vCPUs)  HOG_PRIO (default 10)
set -euo pipefail
source "$(dirname "$0")/common.sh"

LABEL="${1:-qnx}"
HOG_THREADS="${HOG_THREADS:-8}"
HOG_PRIO="${HOG_PRIO:-10}"
PX4_ROOT="${PX4_ROOT:-/data/px4}"
QNX_SDP="${QNX_SDP:-$HOME/qnx800}"
vm() { timeout "${VM_TIMEOUT:-60}" "$SCRIPTS/vm-ssh.sh" "$@"; }
px4cmd() { "$SCRIPTS/px4-vm.sh" cmd "$@"; }

export TMPDIR="${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}"
mkdir -p "$TMPDIR"
bash -c "source '$QNX_SDP/qnxsdp-env.sh' >/dev/null; qcc -Vgcc_ntox86_64 -O2 -o '$TMPDIR/hog' '$BENCH_DIR/hog.c'"
vm "slay -f -Q hog 2>/dev/null; mkdir -p $PX4_ROOT/bench && rm -f $PX4_ROOT/bench/hog && cat > $PX4_ROOT/bench/hog && chmod +x $PX4_ROOT/bench/hog" < "$TMPDIR/hog"

measure() { # label
    px4cmd perf reset >/dev/null
    sleep "$PHASE_S"
    px4cmd perf | perf_to_json "$1"
}

out="$RESULTS/$LABEL.jsonl"
: > "$out"

"$SCRIPTS/px4-vm.sh" status || "$SCRIPTS/px4-vm.sh" start >/dev/null
sleep 10

log "idle ${PHASE_S} s"
measure "$LABEL idle" | tee -a "$out"

log "hog: $HOG_THREADS busy threads at priority $HOG_PRIO for ${PHASE_S} s"
# One VM command: reset counters, run the hog in the foreground (it stops by
# itself), read counters. A hog above the sshd priority can starve the ssh
# session, so nothing here needs the network while the hog runs.
VM_TIMEOUT=$((PHASE_S + 60)) vm "cd $PX4_ROOT/rootfs || exit 1
    ../bin/px4-perf reset > /dev/null
    # run the check above the hog so it is not starved
    on -p 252f sh -c 'sleep 2; pidin -p hog -F %p > $PX4_ROOT/bench/hog_prio.txt' &
    on -p $HOG_PRIO $PX4_ROOT/bench/hog $HOG_THREADS $PHASE_S
    ../bin/px4-perf" | perf_to_json "$LABEL hog ${HOG_THREADS}x prio ${HOG_PRIO}" | tee -a "$out"
seen="$(vm "tail -n +2 $PX4_ROOT/bench/hog_prio.txt" | sort -u | tr -d ' \n')"
log "hog threads ran at priority/policy: $seen"
log "results in $out"
