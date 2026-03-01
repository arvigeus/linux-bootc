#!/usr/bin/env bash
## Install media codecs (requires RPM Fusion)
## https://rpmfusion.org/Howto/Multimedia
set -oue pipefail

dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf group install -y multimedia \
    --setopt="install_weak_deps=False" \
    --exclude=PackageKit-gstreamer-plugin
