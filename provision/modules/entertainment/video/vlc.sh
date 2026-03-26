#!/usr/bin/env bash
## VLC media player
## https://www.videolan.org/
set -oue pipefail

packages=(
    vlc
)

case "$PACKAGE_MANAGER" in
    dnf)    dnf install -y "${packages[@]}" ;;
    pacman) pacman -S --noconfirm --needed "${packages[@]}" ;;
esac
