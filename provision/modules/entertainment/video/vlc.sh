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
config='
[core]
video-filter=pause_click
control=pause_click
snapshot-path=~/Pictures
snapshot-prefix=vlc-
audio-language=jpn,jp,eng,en
sub-language=eng,en,bg,vi,vn
one-instance=1
playlist-enqueue=1

[qt]
qt-minimal-view=1
qt-system-tray=0
qt-pause-minimized=1
qt-dark-palette=1
qt-max-volume=200

[subsdec]
subsdec-encoding=Windows-1251
'

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

VLCRC="$HOME/.config/vlc/vlcrc"
run_unprivileged mkdir -p "$(dirname "$VLCRC")"
# VLC's parser requires `key=value` with no spaces
run_unprivileged crudini --ini-options=nospace --merge "$VLCRC" <<<"$config"
