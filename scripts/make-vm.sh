#!/usr/bin/env bash
# Build a QNX 8.0 QEMU x86_64 image for PX4 with mkqnximage.
# Output goes to $VM_DIR (default ~/qnx-vm-px4). Needs the QNX SDP and an ssh
# public key for root login (default ~/.ssh/id_ed25519_qnx.pub).
set -euo pipefail

QNX_SDP="${QNX_SDP:-$HOME/qnx800}"
VM_DIR="${VM_DIR:-$HOME/qnx-vm-px4}"
SSH_PUB="${SSH_PUB:-$HOME/.ssh/id_ed25519_qnx.pub}"
# Extra MB for /data: PX4 binary (~10 MB stripped), ROMFS, params, dataman, logs.
DATA_SIZE_MB="${DATA_SIZE_MB:-1024}"

[ -f "$SSH_PUB" ] || { echo "missing ssh public key $SSH_PUB" >&2; exit 1; }

export TMPDIR="${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}"
mkdir -p "$TMPDIR" "$VM_DIR"
cd "$VM_DIR"

# shellcheck disable=SC1091
source "$QNX_SDP/qnxsdp-env.sh" >/dev/null
mkqnximage \
    --type=qemu --arch=x86_64 --cpu=4 --ram=2G \
    --hostname=px4-qnx \
    --data-size="$DATA_SIZE_MB" --data-inodes=20000 \
    --ssh-ident="$SSH_PUB" \
    --noprompt --build --force

echo "VM image ready in $VM_DIR/output"
