#!/usr/bin/env bash
# Reproducibility check: clone this repo into an empty directory and run the
# whole pipeline with no manual steps, using its own VM dir and ssh port so
# an existing setup is not touched.
#
# Usage: fresh-clone-test.sh [repo-url-or-path] [dest-dir]
set -euo pipefail

SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
DEST="${2:-$HOME/px4-qnx-fresh}"
export VM_DIR="${VM_DIR:-$HOME/qnx-vm-px4-fresh}"
export SSH_PORT="${SSH_PORT:-2223}"

[ ! -e "$DEST" ] || { echo "$DEST exists; remove it or pick another dest" >&2; exit 1; }
mkdir -p "$DEST"
cd "$DEST"
step() { echo; echo "=== $* ($(date +%T))"; }

step clone;          git clone -q "$SRC" px4-qnx
cd px4-qnx
step fetch-upstream; scripts/fetch-upstream.sh
step apply-patches;  scripts/apply-patches.sh
step setup-venv;     scripts/setup-venv.sh
step build;          scripts/build.sh
step make-vm;        scripts/make-vm.sh
step run-vm;         scripts/run-vm.sh
trap 'kill "$(cat "$VM_DIR/output/qemu.pid")" 2>/dev/null || true' EXIT
step deploy;         scripts/deploy.sh
step tests;          tests/run-all.sh
step done;           echo "FRESH CLONE TEST PASSED in $DEST (VM $VM_DIR, ssh port $SSH_PORT)"
