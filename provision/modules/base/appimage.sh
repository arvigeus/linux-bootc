#!/usr/bin/env bash
## AppImage support (requires FUSE)
set -oue pipefail

case "$PACKAGE_MANAGER" in
dnf) dnf install -y fuse-libs ;;
pacman) pacman -Sy --noconfirm --needed fuse2 ;;
esac

flatpak install --noninteractive --user flathub it.mijorus.gearlever

# Convenience command so users can type `gearlever` instead of the full flatpak invocation
bash_alias gearlever gearlever "flatpak run it.mijorus.gearlever"

# Auto-update AppImages after every package transaction
if [[ "$IS_CONTAINER" != true ]]; then
	case "$PACKAGE_MANAGER" in
	dnf)
		dnf install -y libdnf5-plugin-actions
		fs_write /etc/dnf/libdnf5-plugins/actions.d/gearlever.actions <<'ACTIONS'
post_transaction::::/bin/sh -c '/usr/bin/flatpak run it.mijorus.gearlever --update --all --yes || true'
ACTIONS
		;;
	pacman)
		fs_write /etc/pacman.d/hooks/gearlever-update.hook <<'HOOK'
[Trigger]
Operation = Upgrade
Type = Package
Target = *

[Action]
Description = Updating AppImages...
When = PostTransaction
Depends = flatpak
Exec = /bin/sh -c '/usr/bin/flatpak run it.mijorus.gearlever --update --all --yes || true'
HOOK
		;;
	esac
fi
