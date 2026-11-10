#!/usr/bin/env bash
# Build (if needed) and run stock Linux SITL with the SIH quad, as a baseline
# for comparing against QNX. Runs PX4 in daemon mode; stop with: pkill -x px4
# Usage: run-linux-sitl.sh [--clean-params]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
PX4_DIR="$WORK_DIR/PX4-Autopilot"
export PATH="$WORK_DIR/venv/bin:$PATH"
# CMake 4.x rejects cmake_minimum_required < 3.5 in some PX4 submodules.
export CMAKE_POLICY_VERSION_MINIMUM=3.5

make -C "$PX4_DIR" px4_sitl_default >/dev/null

cd "$PX4_DIR/build/px4_sitl_default/rootfs"
if [ "${1:-}" = "--clean-params" ]; then
    rm -f parameters*.bson dataman
fi
PX4_SIM_MODEL=sihsim_quadx PX4_SIMULATOR=sihsim nohup ../bin/px4 -d > "$WORK_DIR/linux-sitl.log" 2>&1 &
echo "PX4 Linux SITL started (pid $!), log: $WORK_DIR/linux-sitl.log"
