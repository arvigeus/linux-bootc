#!/usr/bin/env bash
## Package manager helpers.
##
## pkg_install / pkg_remove / pkg_is_installed
##   Per-PM install/remove/query, routed through the appropriate shim so
##   declared package state is recorded for reconciliation.
##
## pkg_from_source <build_fn> [build_dep ...]
##   Run a build callback with transient build dependencies. Packages not
##   already installed are removed when the callback returns (or fails —
##   cleanup runs via trap RETURN).
##
##   Example:
##     install_uosc() {
##         local tag tmpdir
##         tag=$(github_latest_tag tomasklaen/uosc)
##         ...
##     }
##     pkg_from_source install_uosc golang
##
##   The build callback must use shimmed file commands (cp, install, ln,
##   mv, rm, touch) so file tracking records its outputs. Files written
##   through unshimmed paths (raw shell redirects, sed -i without a
##   trailing touch, tar extracting directly into /) won't be cleaned
##   up if this call is later removed from the script.
##   See docs/file-tracking.md.

pkg_is_installed() {
	case "$PACKAGE_MANAGER" in
	dnf) rpm -q "$1" &>/dev/null ;;
	pacman) pacman -Qi "$1" &>/dev/null ;;
	esac
}

pkg_install() {
	case "$PACKAGE_MANAGER" in
	dnf) dnf install -y "$@" ;;
	pacman) pacman -S --noconfirm --needed "$@" ;;
	esac
}

pkg_remove() {
	case "$PACKAGE_MANAGER" in
	dnf) dnf remove -y "$@" ;;
	pacman) pacman -Rns --noconfirm "$@" ;;
	esac
}

pkg_from_source() {
	local build_fn=$1
	shift

	local pkg
	local to_remove=()
	for pkg in "$@"; do
		pkg_is_installed "$pkg" || to_remove+=("$pkg")
	done

	(("${#to_remove[@]}")) && pkg_install "${to_remove[@]}"

	# Run build_fn but capture its exit so we always reach cleanup even under
	# `set -e`. Avoids `trap RETURN`, which fires globally on every subsequent
	# function return and tripped `set -u` by referencing an out-of-scope var.
	local rc=0
	"$build_fn" || rc=$?

	(("${#to_remove[@]}")) && pkg_remove "${to_remove[@]}"

	return "$rc"
}
