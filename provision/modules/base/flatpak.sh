#!/usr/bin/env bash
## Configure Flatpak
## https://wiki.archlinux.org/title/Flatpak
set -oue pipefail

# Arch doesn't include flatpak by default
if [[ "$DISTRO" == "arch" ]]; then
    pacman -Sy --noconfirm --needed flatpak
fi

flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-add --if-not-exists flathub-beta \
    https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo
