#!/usr/bin/env bash
## Pacman + Paru (AUR) package reconciliation
##
## Pre-reconciliation:  seed base lists if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra
##
## Native packages → pacman.list / pacman.base.list
## AUR packages    → paru.list   / paru.base.list

_query_pacman() {
	local all_explicit foreign_only
	all_explicit=$(/usr/bin/pacman -Qqe 2>/dev/null | sort -u)
	foreign_only=$(/usr/bin/pacman -Qqem 2>/dev/null | sort -u)
	NATIVE_INSTALLED=$(comm -23 <(echo "$all_explicit") <(echo "$foreign_only"))
	FOREIGN_INSTALLED="$foreign_only"
}

reconcile_pacman_packages_pre() {
	echo "=== Pacman Package Reconciliation (pre) ==="

	_query_pacman
	seed_base_list "${PKG_STATE_DIR}/pacman.base.list" "$NATIVE_INSTALLED" "native packages"
	seed_base_list "${PKG_STATE_DIR}/paru.base.list" "$FOREIGN_INSTALLED" "AUR packages"
}

reconcile_pacman_packages_post() {
	echo "=== Pacman Package Reconciliation (post) ==="

	_query_pacman
	reconcile_post "${PKG_STATE_DIR}/pacman.list" "${PKG_STATE_DIR}/pacman.base.list" "$NATIVE_INSTALLED" "Native packages"
	reconcile_post "${PKG_STATE_DIR}/paru.list" "${PKG_STATE_DIR}/paru.base.list" "$FOREIGN_INSTALLED" "AUR packages"
}

# Implementation of remove/install for pacman
_remove_extra_packages() {
	/usr/bin/pacman -Rns --noconfirm "$@"
	echo "  Removed $# package(s)."
}

_install_missing_packages() {
	# Separate native from AUR
	local -a native=() aur=()
	for pkg in "$@"; do
		if /usr/bin/pacman -Si "$pkg" &>/dev/null; then
			native+=("$pkg")
		else
			aur+=("$pkg")
		fi
	done
	[[ ${#native[@]} -gt 0 ]] && /usr/bin/pacman -S --noconfirm --needed "${native[@]}"
	[[ ${#aur[@]} -gt 0 ]] && /usr/bin/paru -S --noconfirm --needed "${aur[@]}"
	echo "  Installed $# package(s)."
}

# Run based on mode
case "$MODE" in
pre) reconcile_pacman_packages_pre ;;
post) reconcile_pacman_packages_post ;;
esac
