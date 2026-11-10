#!/usr/bin/env bash
# Boot the PX4 QNX VM with QEMU user-mode networking (no sudo needed).
# Guest reaches the host at 10.0.2.2, so PX4 MAVLink to QGroundControl/MAVSDK
# needs no port forward. SSH: localhost:$SSH_PORT -> guest :22.
#
# Usage: run-vm.sh        # headless, console in $VM_DIR/output/qemu.out
#        run-vm.sh -f     # foreground, serial console here (Ctrl-a x quits)
# Stop:  kill "$(cat "$VM_DIR/output/qemu.pid")"
set -euo pipefail

VM_DIR="${VM_DIR:-$HOME/qnx-vm-px4}"
SSH_PORT="${SSH_PORT:-2222}"
cd "$VM_DIR"

console=(-serial file:output/qemu.out -display none -daemonize)
if [ "${1:-}" = "-f" ]; then
    console=(-serial mon:stdio -nographic)
else
    rm -f output/qemu.out
fi

qemu-system-x86_64 \
    -enable-kvm -cpu host -smp 4 -m 2G \
    -kernel output/ifs.bin \
    -drive file=output/disk-qemu.vmdk,if=ide,id=drv0 \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22 \
    -device virtio-net-pci,netdev=net0 \
    -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 \
    -pidfile output/qemu.pid \
    "${console[@]}"

if [ "${1:-}" != "-f" ]; then
    # wait for sshd
    for _ in $(seq 1 300); do
        if "$(dirname "$0")/vm-ssh.sh" true 2>/dev/null; then
            echo "VM up (ssh port $SSH_PORT)"
            exit 0
        fi
        sleep 1
    done
    echo "VM did not answer on ssh within 300 s; see $VM_DIR/output/qemu.out" >&2
    exit 1
fi
