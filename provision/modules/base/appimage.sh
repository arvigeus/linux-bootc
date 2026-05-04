#!/usr/bin/env bash
## AppImage support (requires FUSE + appiget CLI)
##
## Installs system dependencies and the appimageupdatetool utility for faster updates.
## The appiget CLI itself is installed system-wide by the build process.
set -oue pipefail

case "$PACKAGE_MANAGER" in
dnf) dnf install -y fuse-libs ;;
pacman) pacman -S --noconfirm --needed fuse2 ;;
esac

# Efficient delta updates
appiget install AppImageCommunity/AppImageUpdate \
	--pattern 'appimageupdatetool-x86_64.AppImage' \
	--name appimageupdatetool \
	--noninteractive

# Auto-update AppImages after every package transaction
if [[ "$IS_CONTAINER" != true ]]; then
	case "$PACKAGE_MANAGER" in
	dnf)
		dnf install -y libdnf5-plugin-actions
		fs_write /etc/dnf/libdnf5-plugins/actions.d/appimage-update.actions <<'ACTIONS'
post_transaction::::/bin/sh -c '/usr/local/bin/appiget update --noninteractive || true'
ACTIONS
		;;
	pacman)
		fs_write /etc/pacman.d/hooks/appimage-update.hook <<'HOOK'
[Trigger]
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Updating AppImages...
When = PostTransaction
Exec = /bin/sh -c '/usr/local/bin/appiget update --noninteractive || true'
HOOK
		;;
	esac
fi
