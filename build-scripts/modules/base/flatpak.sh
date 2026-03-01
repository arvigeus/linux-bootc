#!/usr/bin/env bash
## Configure Flathub remote for flatpak
set -oue pipefail

# Drop the remote config so flatpak picks it up automatically
mkdir -p /etc/flatpak/remotes.d
curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
    https://dl.flathub.org/repo/flathub.flatpakrepo
