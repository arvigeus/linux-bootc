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
        [[ "$IS_CONTAINER" != true ]] && packages+=(libdnf5-plugin-actions)
        dnf install -y "${packages[@]}"
        ;;
    pacman) pacman -S --noconfirm --needed "${packages[@]}" ;;
esac

# Periodic firmware metadata refresh
systemctl enable fwupd-refresh.timer

# Baremetal: auto-apply firmware updates after every package transaction.
# TODO: Containers have no post-transaction hook — find a way to auto-apply firmware updates.
if [[ "$IS_CONTAINER" != true ]]; then
    case "$PACKAGE_MANAGER" in
        dnf)
            mkdir -p /etc/dnf/libdnf5-plugins/actions.d
            touch /etc/dnf/libdnf5-plugins/actions.d/fwupd.actions
            cat > /etc/dnf/libdnf5-plugins/actions.d/fwupd.actions <<'ACTIONS'
post_transaction::::/bin/sh -c '/usr/bin/fwupdmgr update --no-reboot-check || true'
ACTIONS
            touch /etc/dnf/libdnf5-plugins/actions.d/fwupd.actions
            ;;
        pacman)
            mkdir -p /etc/pacman.d/hooks
            touch /etc/pacman.d/hooks/fwupd-update.hook
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
            touch /etc/pacman.d/hooks/fwupd-update.hook
            ;;
    esac
fi
