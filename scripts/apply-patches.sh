#!/usr/bin/env bash
# Apply patches/*.patch on top of the pinned PX4 tag (run fetch-upstream.sh first).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$REPO_DIR/../work}"
PX4_DIR="$WORK_DIR/PX4-Autopilot"

cd "$PX4_DIR"
git -c user.name="${GIT_AUTHOR_NAME:-px4-qnx}" -c user.email="${GIT_AUTHOR_EMAIL:-px4-qnx@localhost}" \
    am --keep-cr "$REPO_DIR"/patches/*.patch
git log --oneline -n "$(ls "$REPO_DIR"/patches/*.patch | wc -l)"
