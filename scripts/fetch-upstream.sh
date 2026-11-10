#!/usr/bin/env bash
# Clone PX4 Autopilot at the pinned tag into ../work/PX4-Autopilot and
# create the qnx-port branch. Safe to re-run.
set -euo pipefail

TAG="${PX4_TAG:-v1.17.0}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
PX4_DIR="$WORK_DIR/PX4-Autopilot"

mkdir -p "$WORK_DIR"

if [ ! -d "$PX4_DIR/.git" ]; then
    git clone --branch "$TAG" --depth 1 --recursive --shallow-submodules \
        https://github.com/PX4/PX4-Autopilot.git "$PX4_DIR"
else
    echo "PX4 already cloned at $PX4_DIR"
fi

cd "$PX4_DIR"
git submodule update --init --recursive --depth 1
if ! git rev-parse --verify -q qnx-port >/dev/null; then
    git checkout -b qnx-port "$TAG"
fi
echo "PX4 $(git describe --tags --always) ready at $PX4_DIR (branch $(git branch --show-current))"
