#!/usr/bin/env bash
## Configure Flatpak
## https://flatpak.org/
set -oue pipefail

# Arch doesn't include flatpak by default
if [[ "$DISTRO" == "arch" ]]; then
    pacman -Sy --noconfirm --needed flatpak
fi

flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-add --if-not-exists flathub-beta \
    https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo

# Auto-update flatpaks after every package transaction
if [[ "$IS_CONTAINER" != true ]]; then
    case "$PACKAGE_MANAGER" in
        dnf)
            dnf install -y libdnf5-plugin-actions
            fs_write /etc/dnf/libdnf5-plugins/actions.d/flatpak.actions <<'ACTIONS'
post_transaction::::/bin/sh -c '/usr/bin/flatpak update -y || true'
ACTIONS
            ;;
        pacman)
            fs_write /etc/pacman.d/hooks/flatpak-update.hook <<'HOOK'
[Trigger]
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Updating flatpaks...
When = PostTransaction
Depends = flatpak
Exec = /bin/sh -c '/usr/bin/flatpak update -y || true'
HOOK
            ;;
    esac
fi
