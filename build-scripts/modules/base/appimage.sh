#!/usr/bin/env bash
## AppImage support (requires FUSE)
set -oue pipefail

case "$PACKAGE_MANAGER" in
    dnf)    dnf install -y fuse-libs ;;
    pacman) pacman -Sy --noconfirm --needed fuse2 ;;
esac
