#!/usr/bin/env bash
# Run a command (or a shell) in the PX4 QNX VM as root.
exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    -o ConnectTimeout=3 -o BatchMode=yes \
    -i "${SSH_KEY:-$HOME/.ssh/id_ed25519_qnx}" -p "${SSH_PORT:-2222}" root@localhost "$@"
