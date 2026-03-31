#!/usr/bin/env bash
## Tools for managing config files
set -oue pipefail

packages=(
	crudini # INI file editor
	yq      # YAML processor
	jq      # JSON processor
)

case "$PACKAGE_MANAGER" in
dnf) dnf install -y "${packages[@]}" ;;
pacman) pacman -Sy --noconfirm --needed "${packages[@]}" ;;
esac
