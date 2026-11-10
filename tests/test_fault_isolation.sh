#!/usr/bin/env bash
# Fault isolation on QNX: during a full MAVSDK mission (tests/test_flight.py),
#   1. a separate process (bench/badapp.c) burns 8 threads of CPU, takes
#      512 MiB, then crashes with SIGSEGV;
#   2. PX4's logger module is stopped and started again in flight.
# Asserts: the flight test still passes, PX4 is still running, the crash left
# a core file from the QNX dumper, and the rate controller kept its rate.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

QNX_SDP="${QNX_SDP:-$HOME/qnx800}"
PY="${PYTHON:-$REPO_DIR/../work/venv/bin/python}"
export TMPDIR="${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}"
mkdir -p "$TMPDIR"

bash -c "source '$QNX_SDP/qnxsdp-env.sh' >/dev/null; qcc -Vgcc_ntox86_64 -O0 -o '$TMPDIR/badapp' '$REPO_DIR/bench/badapp.c'"
vm "slay -f -Q badapp 2>/dev/null; mkdir -p $PX4_ROOT/bench && rm -f $PX4_ROOT/bench/badapp /data/var/dumper/badapp.core && cat > $PX4_ROOT/bench/badapp && chmod +x $PX4_ROOT/bench/badapp" < "$TMPDIR/badapp"

ensure_px4
px4_pid_before="$(vm "pidin -p px4 -F '%a'" | tail -n +2 | head -1 | tr -d ' ')"

flight_log="$TMPDIR/fault_flight.log"
timeout 600 "$PY" "$TESTS_DIR/test_flight.py" > "$flight_log" 2>&1 &
flight=$!

# wait until the mission is running
for _ in $(seq 1 180); do
    grep -q "mission started" "$flight_log" && break
    kill -0 $flight 2>/dev/null || break
    sleep 1
done
grep -q "mission started" "$flight_log" || { cat "$flight_log"; fail "mission never started"; }

info "mission running: starting badapp (8 threads, 512 MiB, crash after 8 s) at priority 10"
px4cmd perf reset >/dev/null
# reset + badapp + perf read in one VM command so the counter covers exactly the bad app's lifetime
VM_TIMEOUT=30 vm "cd $PX4_ROOT/rootfs && ../bin/px4-perf reset > /dev/null
    on -p 10 $PX4_ROOT/bench/badapp 8 512 8 > $PX4_ROOT/bench/badapp.out 2>&1; echo exit=\$? >> $PX4_ROOT/bench/badapp.out
    ../bin/px4-perf | grep 'mc_rate_control: interval' > $PX4_ROOT/bench/badapp_perf.txt" || true
vm "cat $PX4_ROOT/bench/badapp.out" | sed 's/^/    /'

info "stopping and restarting the PX4 logger in flight"
px4cmd logger stop >/dev/null 2>&1 || true
sleep 2
px4cmd logger on >/dev/null 2>&1 || px4cmd logger start >/dev/null 2>&1 || true
rate_line="$(vm "cat $PX4_ROOT/bench/badapp_perf.txt" || true)"
info "rate controller while badapp ran (~8 s, expect ~6400 at 800 Hz): ${rate_line#*interval: }"

wait $flight && flight_rc=0 || flight_rc=$?
grep "test_flight" "$flight_log" | sed 's/^/    /'

px4_pid_after="$(vm "pidin -p px4 -F '%a'" | tail -n +2 | head -1 | tr -d ' ')"
core="$(vm "ls /data/var/dumper/ 2>/dev/null" | grep -c badapp || true)"
logger_ok="$(px4cmd logger status 2>&1 | grep -ci "running\|Full log" || true)"

[ "$flight_rc" -eq 0 ] || fail "flight test failed during the fault"
[ -n "$px4_pid_after" ] && [ "$px4_pid_after" = "$px4_pid_before" ] || fail "PX4 restarted or died (pid $px4_pid_before -> $px4_pid_after)"
vm "grep -q 'crashing now' $PX4_ROOT/bench/badapp.out" || fail "badapp did not reach its crash"
[ "$core" -ge 1 ] || fail "no badapp core file in /data/var/dumper"
[ "$logger_ok" -ge 1 ] || fail "logger not running again after restart"
events="$(echo "$rate_line" | awk '{print $3}')"
[ -n "$events" ] || fail "no rate controller perf data"
[ "$events" -gt 6000 ] || fail "rate controller only ran $events times while badapp ran"

pass "mission completed while a separate process hogged CPU+RAM and segfaulted, and the logger was restarted; PX4 pid $px4_pid_after unchanged, core file written"
