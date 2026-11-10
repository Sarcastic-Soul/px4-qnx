#!/usr/bin/env bash
# Configure and build PX4 (qnx_sitl_default) for QNX 8.0 x86_64 with qcc.
# Code generation (uORB, params, MAVLink) runs on the host with the venv Python.
# Usage: build.sh [--configure-only] [extra ninja args]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
PX4_DIR="$WORK_DIR/PX4-Autopilot"
BUILD_DIR="${BUILD_DIR:-$PX4_DIR/build/qnx_sitl_default}"
QNX_SDP="${QNX_SDP:-$HOME/qnx800}"

# qcc writes big temp files; host /tmp may be a small tmpfs with a quota.
export TMPDIR="${TMPDIR_QNX:-$HOME/qnx-vm/.tmp}"
mkdir -p "$TMPDIR"

# shellcheck disable=SC1091
source "$QNX_SDP/qnxsdp-env.sh" >/dev/null
export PATH="$WORK_DIR/venv/bin:$PATH"
# CMake 4.x rejects cmake_minimum_required < 3.5 in some PX4 submodules.
export CMAKE_POLICY_VERSION_MINIMUM=3.5

configure_only=0
if [ "${1:-}" = "--configure-only" ]; then
    configure_only=1
    shift
fi

cmake -S "$PX4_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCONFIG=qnx_sitl_default \
    -DPYTHON_EXECUTABLE="$WORK_DIR/venv/bin/python"

if [ "$configure_only" = 1 ]; then
    exit 0
fi

ninja -C "$BUILD_DIR" "$@"
file "$BUILD_DIR/bin/px4"
