#!/usr/bin/env bash
## Install media codecs
set -oue pipefail

if [[ "$DISTRO" == "fedora" ]]; then
	# https://rpmfusion.org/Howto/Multimedia
	dnf swap -y ffmpeg-free ffmpeg --allowerasing
	dnf group install -y multimedia \
		--setopt="install_weak_deps=False" \
		--exclude=PackageKit-gstreamer-plugin
fi
