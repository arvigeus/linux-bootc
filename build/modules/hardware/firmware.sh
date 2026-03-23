#!/usr/bin/env bash
## Firmware update daemon (fwupd)
## https://fwupd.org/
set -oue pipefail

# https://wiki.archlinux.org/title/Fwupd
packages=(
    fwupd
)

case "$PACKAGE_MANAGER" in
    dnf)
        [[ ! -f /run/.containerenv ]] && packages+=(libdnf5-plugin-actions)
        dnf install -y "${packages[@]}"
        ;;
    pacman) pacman -S --noconfirm --needed "${packages[@]}" ;;
esac

# Periodic firmware metadata refresh
systemctl enable fwupd-refresh.timer

# Baremetal: auto-apply firmware updates after every package transaction.
# TODO: Containers have no post-transaction hook — find a way to auto-apply firmware updates.
if [[ ! -f /run/.containerenv ]]; then
    case "$PACKAGE_MANAGER" in
        dnf)
            mkdir -p /etc/dnf/libdnf5-plugins/actions.d
            cat > /etc/dnf/libdnf5-plugins/actions.d/fwupd.actions <<'ACTIONS'
post_transaction::::/bin/sh -c '/usr/bin/fwupdmgr update --no-reboot-check || true'
ACTIONS
            ;;
        pacman)
            mkdir -p /etc/pacman.d/hooks
            cat > /etc/pacman.d/hooks/fwupd-update.hook <<'HOOK'
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
