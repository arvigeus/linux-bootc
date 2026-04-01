#!/usr/bin/env bash
## micro - a modern and intuitive terminal-based text editor
## https://micro-editor.github.io/
set -oue pipefail

packages=(
	micro
)

# Install packages
case "$PACKAGE_MANAGER" in
dnf) dnf install -y "${packages[@]}" ;;
pacman) pacman -S --noconfirm --needed "${packages[@]}" ;;
esac

## Keybindings:
# `Ctrl + Q`: Quit
# `Ctrl + C`: Copy
# `Ctrl + V`: Paste
# `Ctrl + Z`: Undo
