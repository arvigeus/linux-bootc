#!/usr/bin/env bash
## Configure Flatpak
set -oue pipefail

# Arch doesn't include flatpak by default
if [[ "$DISTRO" == "arch" ]]; then
    pacman -Sy --noconfirm --needed flatpak
fi

# Add Flathub remotes (not available by default)
if [[ -f /run/.containerenv ]]; then
    mkdir -p /etc/flatpak/remotes.d
    curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub-beta.flatpakrepo \
        https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo
else
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak remote-add --if-not-exists flathub-beta \
        https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo
fi
