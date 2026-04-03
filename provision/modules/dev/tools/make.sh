#!/usr/bin/env bash
set -oue pipefail

fs_write /etc/makepkg.conf.d/makeflags.conf <<EOF
MAKEFLAGS="--jobs=$(nproc)"
EOF
