#!/usr/bin/env bash
# Start / stop / query PX4 SIH inside the QNX VM.
#
# Usage: px4-vm.sh start [--clean]   # --clean wipes params, dataman, logs
#        px4-vm.sh stop
#        px4-vm.sh status            # exit 0 if running
#        px4-vm.sh cmd <px4 command> # e.g. px4-vm.sh cmd commander status
#        px4-vm.sh log
#
# MAVLink goes to the host at $PX4_MAVLINK_PARTNER_IP (QEMU user NAT: 10.0.2.2),
# GCS on UDP 14550, offboard/MAVSDK on UDP 14540.
set -euo pipefail

SSH="$(cd "$(dirname "$0")" && pwd)/vm-ssh.sh"
PX4_ROOT="${PX4_ROOT:-/data/px4}"
PARTNER="${PX4_MAVLINK_PARTNER_IP:-10.0.2.2}"
MODEL="${PX4_SIM_MODEL:-sihsim_quadx}"

vm() { timeout "${VM_TIMEOUT:-60}" "$SSH" "$@"; }

running() { vm "pidin -p px4 -F '%a' 2>/dev/null | grep -q '[0-9]'"; }

case "${1:-}" in
start)
    if running; then echo "PX4 already running"; exit 0; fi
    clean=""
    [ "${2:-}" = "--clean" ] && clean="rm -rf parameters*.bson dataman log;"
    vm "mkdir -p $PX4_ROOT/rootfs && cd $PX4_ROOT/rootfs && $clean \
        PX4_SIM_MODEL=$MODEL PX4_MAVLINK_PARTNER_IP=$PARTNER \
        nohup ../bin/px4 -d $PX4_ROOT/etc > $PX4_ROOT/px4.log 2>&1 < /dev/null &"
    for _ in $(seq 1 30); do
        if vm "cd $PX4_ROOT/rootfs && ../bin/px4-commander status" >/dev/null 2>&1; then
            echo "PX4 started in VM ($MODEL, MAVLink partner $PARTNER)"
            exit 0
        fi
        sleep 1
    done
    echo "PX4 did not come up; log:" >&2
    vm "cat $PX4_ROOT/px4.log" >&2 || true
    exit 1
    ;;
stop)
    if running; then
        vm "cd $PX4_ROOT/rootfs && ../bin/px4-shutdown" >/dev/null 2>&1 || true
        for _ in $(seq 1 10); do running || break; sleep 1; done
        running && vm "slay -f px4" || true
    fi
    echo "PX4 stopped"
    ;;
status)
    running
    ;;
cmd)
    shift
    vm "cd $PX4_ROOT/rootfs && ../bin/px4-$*"
    ;;
log)
    vm "cat $PX4_ROOT/px4.log"
    ;;
*)
    sed -n '2,10p' "$0"
    exit 2
    ;;
esac
