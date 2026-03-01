#!/usr/bin/env bash
## AppImage support (requires FUSE)
set -oue pipefail

if [[ "$DISTRO" == "fedora" ]]; then
    dnf install -y fuse-libs
fi
