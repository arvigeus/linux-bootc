#!/usr/bin/env bash
## Nano - Text Editor
## https://www.nano-editor.org/
set -oue pipefail

packages=(
	nano
)

# --- Static config files ---

# https://www.nano-editor.org/dist/latest/nanorc.5.html
NANORC='
# Syntax highlighting
include "/usr/share/nano/*.nanorc"
include "/usr/share/nano/extra/*.nanorc"
include "/usr/share/nano-syntax-highlighting/*.nanorc"

set autoindent
set linenumbers
set mouse
set smarthome
'

# --- Functions ---

# https://gitlab.archlinux.org/archlinux/packaging/packages/nano-syntax-highlighting/-/blob/main/PKGBUILD
install_nano_syntax_highlighting() {
	local tag tmpdir
	tag=$(github_latest_tag "galenguyer/nano-syntax-highlighting")
	tmpdir=$(mktemp -d)
	curl -L "https://github.com/galenguyer/nano-syntax-highlighting/archive/refs/tags/${tag}.tar.gz" |
		tar -xz --strip-components=1 -C "$tmpdir"
	rm -rf /usr/share/nano-syntax-highlighting
	install -d /usr/share/nano-syntax-highlighting
	cp "$tmpdir"/*.nanorc /usr/share/nano-syntax-highlighting/
	rm -rf "$tmpdir"
}

# --- Install packages ---

case "$PACKAGE_MANAGER" in
dnf)
	dnf install -y "${packages[@]}"
	install_nano_syntax_highlighting
	;;
pacman)
	packages+=(nano-syntax-highlighting)
	pacman -S --noconfirm --needed "${packages[@]}"
	;;
esac

# --- Config ---

fs_write /etc/nanorc <<<"${NANORC#$'\n'}"
