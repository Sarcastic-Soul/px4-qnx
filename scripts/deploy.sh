#!/usr/bin/env bash
# Copy the QNX PX4 build (stripped binary, module symlinks, ROMFS etc/) into
# the VM at $PX4_ROOT (default /data/px4). Keeps rootfs/ (params, logs).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/PX4-Autopilot/build/qnx_sitl_default}"
PX4_ROOT="${PX4_ROOT:-/data/px4}"
QNX_SDP="${QNX_SDP:-$HOME/qnx800}"
SSH="$REPO_DIR/scripts/vm-ssh.sh"

stage="$(mktemp -d "${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}/px4-deploy.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/bin"
cp -a "$BUILD_DIR/bin/." "$stage/bin/"
cp -a "$BUILD_DIR/etc" "$stage/etc"
# The 30 MB debug binary stays on the host for gdb; ship a stripped copy.
"$QNX_SDP/host/linux/x86_64/usr/bin/ntox86_64-strip" -o "$stage/bin/px4" "$BUILD_DIR/bin/px4"

"$SSH" "mkdir -p $PX4_ROOT/rootfs && rm -rf $PX4_ROOT/bin $PX4_ROOT/etc"
tar -C "$stage" -cf - bin etc | "$SSH" "tar -C $PX4_ROOT -xf -"
"$SSH" "ls -l $PX4_ROOT/bin/px4"
echo "deployed to $PX4_ROOT"
