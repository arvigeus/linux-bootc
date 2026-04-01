#!/usr/bin/env bash

fs_write /etc/makepkg.conf.d/makeflags.conf <<EOF
MAKEFLAGS="--jobs=$(nproc)"
EOF
