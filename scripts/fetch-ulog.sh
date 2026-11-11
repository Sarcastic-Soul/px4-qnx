#!/usr/bin/env bash
# Copy the newest ULog from the QNX VM to the host and print a short summary.
# Usage: fetch-ulog.sh [dest_dir]   (default ../work/logs)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
DEST="${1:-$WORK_DIR/logs}"
PX4_ROOT="${PX4_ROOT:-/data/px4}"
SSH="$REPO_DIR/scripts/vm-ssh.sh"
PY="${PYTHON:-$WORK_DIR/venv/bin/python}"

remote="$(timeout 30 "$SSH" "ls -t $PX4_ROOT/rootfs/log/*/*.ulg $PX4_ROOT/rootfs/fs/log/*/*.ulg 2>/dev/null | head -1")"
[ -n "$remote" ] || { echo "no ULog found in VM" >&2; exit 1; }
mkdir -p "$DEST"
local_file="$DEST/qnx-$(basename "$(dirname "$remote")")-$(basename "$remote")"
timeout 120 "$SSH" "cat $remote" > "$local_file"
echo "$local_file"
"$PY" - "$local_file" <<'EOF'
import sys
from pyulog import ULog
u = ULog(sys.argv[1])
dur = (u.last_timestamp - u.start_timestamp) / 1e6
names = sorted({d.name for d in u.data_list})
print(f"duration {dur:.1f} s, {len(names)} topics, sys_name={u.msg_info_dict.get('sys_name')}, "
      f"os={u.msg_info_dict.get('sys_os_name')} {u.msg_info_dict.get('sys_os_ver_release', '')}")
for t in ("vehicle_local_position", "vehicle_angular_velocity", "actuator_motors"):
    print(f"  {t}: {'yes' if t in names else 'MISSING'}")
EOF
