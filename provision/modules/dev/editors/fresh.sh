#!/usr/bin/env bash
## Fresh - The Terminal Text Editor
## https://getfresh.dev/

case "$PACKAGE_MANAGER" in
dnf) dnf install -y fresh ;;
pacman) paru -S --noconfirm --needed fresh-editor-bin ;;
esac
