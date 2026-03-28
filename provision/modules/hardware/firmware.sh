#!/usr/bin/env bash
## Firmware update daemon (fwupd)
## https://fwupd.org/
set -oue pipefail

# https://wiki.archlinux.org/title/Fwupd
packages=(
    fwupd
)

case "$PACKAGE_MANAGER" in
    dnf) dnf install -y "${packages[@]}" ;;
    pacman) pacman -S --noconfirm --needed "${packages[@]}" ;;
esac

# Periodic firmware metadata refresh
systemctl enable fwupd-refresh.timer

# Baremetal: auto-apply firmware updates after every package transaction.
# Containers: handled by deploy/20-firmware.sh (runs once per new image).
if [[ "$IS_CONTAINER" != true ]]; then
    case "$PACKAGE_MANAGER" in
        dnf)
            dnf install -y libdnf5-plugin-actions
            fs_write /etc/dnf/libdnf5-plugins/actions.d/fwupd.actions <<'ACTIONS'
post_transaction::::/bin/sh -c '/usr/bin/fwupdmgr update --no-reboot-check || true'
ACTIONS
            ;;
        pacman)
            fs_write /etc/pacman.d/hooks/fwupd-update.hook <<'HOOK'
[Trigger]
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Applying firmware updates...
When = PostTransaction
Depends = fwupd
Exec = /bin/sh -c '/usr/bin/fwupdmgr update --no-reboot-check || true'
HOOK
            ;;
    esac
fi
