#!/usr/bin/env bash
## Update the system using the native package manager
set -euo pipefail

if command -v dnf &>/dev/null; then
    sudo dnf upgrade -y
elif command -v pacman &>/dev/null; then
    paru -Syu --noconfirm
else
    echo "ERROR: Unsupported package manager" >&2
    exit 1
fi

