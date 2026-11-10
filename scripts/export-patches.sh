#!/usr/bin/env bash
# Regenerate patches/ from the qnx-port branch in ../work/PX4-Autopilot.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
PX4_DIR="$WORK_DIR/PX4-Autopilot"
TAG="${PX4_TAG:-v1.17.0}"

rm -f "$REPO_DIR"/patches/*.patch
git -C "$PX4_DIR" format-patch --quiet --no-signature "$TAG"..qnx-port -o "$REPO_DIR/patches"
ls "$REPO_DIR/patches"
