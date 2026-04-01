#!/usr/bin/env bash
## Syncplay - shared viewing.
## https://syncplay.pl/
set -oue pipefail

packages=(
	syncplay
)

# Install packages
case "$PACKAGE_MANAGER" in
dnf) dnf install -y "${packages[@]}" ;;
pacman)
	packages+=(
		pyside6 # needed for interface (marked as optional for Arch)
	)
	pacman -S --noconfirm --needed "${packages[@]}"
	;;
esac
