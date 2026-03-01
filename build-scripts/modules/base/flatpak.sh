#!/usr/bin/env bash
## Configure Flatpak
set -oue pipefail

if [[ "$DISTRO" == "fedora" ]]; then
	# Add Flathub remote (not available by default)
    mkdir -p /etc/flatpak/remotes.d
    curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
        https://dl.flathub.org/repo/flathub.flatpakrepo
fi
