#!/usr/bin/env bash
# Create ../work/venv with PX4's Python codegen requirements and the host-side
# test tools (MAVSDK gRPC wrapper, pyulog). Needs uv (https://docs.astral.sh/uv/).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
PX4_DIR="$WORK_DIR/PX4-Autopilot"

# PX4 v1.17.0 codegen (empy<4 etc.) is not tested on very new Pythons; pin 3.12.
uv venv --python 3.12 "$WORK_DIR/venv"
VIRTUAL_ENV="$WORK_DIR/venv" uv pip install \
    -r "$PX4_DIR/Tools/setup/requirements.txt" \
    mavsdk-grpc==4.0.5
echo "venv ready: $WORK_DIR/venv"
