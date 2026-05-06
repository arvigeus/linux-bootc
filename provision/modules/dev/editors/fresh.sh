#!/usr/bin/env bash
## Fresh - The Terminal Text Editor
## https://getfresh.dev/
set -oue pipefail

repo_health https://github.com/sinelaw/fresh -m 12

case "$PACKAGE_MANAGER" in
dnf) dnf install -y fresh ;;
pacman) paru -S --noconfirm --needed fresh-editor-bin ;;
esac
