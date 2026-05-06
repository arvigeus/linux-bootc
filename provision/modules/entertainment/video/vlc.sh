#!/usr/bin/env bash
## VLC media player
## https://www.videolan.org/
set -oue pipefail

repo_health https://github.com/nurupo/vlc-pause-click-plugin -m 36

packages=(
	vlc
	vlc-plugins-all
	# vlc-plugin-pause-click
)

# https://wiki.videolan.org/Preferences/
fs_write "$HOME/.config/vlc/vlcrc" <<'EOF'
[core]
metadata-network-access=1
one-instance=1
playlist-enqueue=1
audio-language=jpn,jp,eng,en
sub-language=eng,en,bg,vi,vn
snapshot-path=~/Pictures
snapshot-prefix=vlc-
video-filter=pause_click
control=pause_click

[qt]
qt-privacy-ask=0
qt-minimal-view=1
qt-system-tray=0
qt-pause-minimized=1
qt-dark-palette=1
qt-max-volume=200

# [subsdec]
# subsdec-encoding=Windows-1251
EOF

case "$PACKAGE_MANAGER" in
dnf)
	packages+=(vlc-plugin-pause-click)
	dnf install -y "${packages[@]}"
	;;
pacman)
	pacman -S --noconfirm --needed "${packages[@]}"
	paru -S --noconfirm --needed vlc-pause-click-plugin
	;;
esac
