#!/usr/bin/env bash
## AppImage support (requires FUSE)
set -oue pipefail

if [[ "$PACKAGE_MANAGER" == "dnf" ]]; then
    dnf install -y fuse-libs
fi
