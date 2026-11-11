#!/usr/bin/env bash
# Build the codelab programs with qcc, copy them to the VM, and run both
# experiments from the codelab. Fails if QNX does not behave as the codelab
# says. Needs a running VM (scripts/run-vm.sh) and the QNX SDP.
#
# Usage: codelab/qnx-resmgr-priority/run-demo.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/../.."
QNX_SDP="${QNX_SDP:-$HOME/qnx800}"
export TMPDIR="${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}"
OUT="$TMPDIR/qnx-resmgr-priority"
mkdir -p "$OUT"

fail() { echo "FAIL: $*" >&2; exit 1; }

# shellcheck disable=SC1091
source "$QNX_SDP/qnxsdp-env.sh" >/dev/null
CFLAGS=(-Vgcc_ntox86_64 -Wall -Wextra -Werror -O2)
qcc "${CFLAGS[@]}" -o "$OUT/prio_dev" "$DIR/src/prio_dev.c"
qcc "${CFLAGS[@]}" -DFIXED -o "$OUT/prio_dev_fixed" "$DIR/src/prio_dev.c"
qcc "${CFLAGS[@]}" -o "$OUT/prio_read" "$DIR/src/prio_read.c"
qcc "${CFLAGS[@]}" -o "$OUT/prio_tick" "$DIR/src/prio_tick.c"
qcc "${CFLAGS[@]}" -o "$OUT/hog" "$ROOT/bench/hog.c"

vm() { "$ROOT/scripts/vm-ssh.sh" "$@"; }
vm 'mkdir -p /data/codelab'
scp -O -q -P "${SSH_PORT:-2222}" -i "${SSH_KEY:-$HOME/.ssh/id_ed25519_qnx}" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "$OUT"/* root@localhost:/data/codelab/

echo "== Step: who runs the server?"
basic="$(vm 'cd /data/codelab; ./prio_dev & sleep 1; ./prio_read; on -p 60f ./prio_read; on -p 200f ./prio_read; slay -f prio_dev >/dev/null; sleep 1
./prio_dev_fixed & sleep 1; ./prio_read; on -p 60f ./prio_read; on -p 200f ./prio_read; slay -f prio_dev_fixed >/dev/null; true')"
echo "$basic"
echo "$basic" | grep -q 'client_prio=200 .*server_prio=200 ' || fail "default channel did not inherit priority 200"
[ "$(echo "$basic" | grep -c 'server_prio=10 ')" -ge 4 ] || fail "fixed channel did not stay at 10"

echo "== Experiment 1: inheritance lets a client run server work above a control loop"
e1="$(vm 'cd /data/codelab; for d in prio_dev prio_dev_fixed; do on -C 0 ./$d 200 & sleep 1; on -C 0 -p 100f ./prio_tick 2 & sleep 0.5; on -C 0 -p 200f ./prio_read; wait $!; slay -f $d >/dev/null; sleep 1; done; true')"
echo "$e1"
gaps="$(echo "$e1" | sed -n 's/.*worst gap \([0-9.]*\) ms.*/\1/p')"
g_inherit="$(echo "$gaps" | sed -n 1p)"
g_fixed="$(echo "$gaps" | sed -n 2p)"
awk -v a="$g_inherit" 'BEGIN { exit !(a > 150) }' || fail "expected a gap > 150 ms with inheritance, got $g_inherit"
awk -v a="$g_fixed" 'BEGIN { exit !(a < 20) }' || fail "expected a gap < 20 ms with a fixed-priority channel, got $g_fixed"

echo "== Experiment 2: a fixed-priority server can be starved (priority inversion)"
e2="$(vm 'cd /data/codelab; for d in prio_dev prio_dev_fixed; do on -C 0 ./$d 5 & sleep 1; on -C 0 -p 30r ./hog 1 2 >/dev/null & sleep 0.3; on -C 0 -p 60f ./prio_read; sleep 2; slay -f $d >/dev/null; sleep 1; done; true')"
echo "$e2"
times="$(echo "$e2" | sed -n 's/.*took_ms=\([0-9.]*\).*/\1/p')"
t_inherit="$(echo "$times" | sed -n 1p)"
t_fixed="$(echo "$times" | sed -n 2p)"
awk -v a="$t_inherit" 'BEGIN { exit !(a < 50) }' || fail "expected < 50 ms with inheritance, got $t_inherit"
awk -v a="$t_fixed" 'BEGIN { exit !(a > 500) }' || fail "expected > 500 ms with a fixed-priority server under load, got $t_fixed"

echo "PASS: inheritance gap ${g_inherit} ms vs fixed ${g_fixed} ms; inversion: inherit ${t_inherit} ms vs fixed ${t_fixed} ms"
