#!/usr/bin/env bash
## AppImage reconciliation
##
## Pre-reconciliation:  seed base.list if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra
##
## Managed list is derived from .ini files in the state directory.
## Uses appiget as the backend for install/remove/list operations.

APPIMAGE_STATE_DIR="/usr/share/system-state.d/appimage"

_appimage_list_installed() {
	/usr/local/bin/appiget list 2>/dev/null |
		awk 'NR > 2 {print $1}' |
		sort -u
}

# Build a managed list from .ini filenames
_appimage_managed_list() {
	local tmpfile
	tmpfile=$(mktemp)
	for ini in "$APPIMAGE_STATE_DIR"/*.ini; do
		[[ -f "$ini" ]] || continue
		basename "$ini" .ini
	done | sort -u >"$tmpfile"
	echo "$tmpfile"
}

reconcile_appimage_pre() {
	echo "=== AppImage Reconciliation (pre) ==="

	local installed_sorted
	installed_sorted=$(_appimage_list_installed)
	seed_base_list "${APPIMAGE_STATE_DIR}/appimage.base.list" "$installed_sorted" "AppImages"
}

reconcile_appimage_post() {
	echo "=== AppImage Reconciliation (post) ==="

	local installed_sorted
	installed_sorted=$(_appimage_list_installed)

	# Build a temporary managed list file from .ini files
	local managed_list
	managed_list=$(_appimage_managed_list)

	reconcile_post \
		"$managed_list" \
		"${APPIMAGE_STATE_DIR}/appimage.base.list" \
		"$installed_sorted" \
		"AppImages"

	rm -f "$managed_list"
}

# Implementation of remove/install for AppImages (via appiget)
_remove_extra_packages() {
	for app in "$@"; do
		/usr/local/bin/appiget remove "$app" --noninteractive 2>/dev/null || true
	done
	echo "  Removed $# AppImage(s)."
}

_install_missing_packages() {
	for app in "$@"; do
		local ini="${APPIMAGE_STATE_DIR}/${app}.ini"
		if [[ ! -f "$ini" ]]; then
			echo "  WARNING: No INI for ${app} — skipping" >&2
			continue
		fi

		local repo
		repo=$(sed -n 's/^repo=//p' "$ini")

		if [[ -z "$repo" ]]; then
			echo "  WARNING: No repo in INI for ${app} — skipping" >&2
			continue
		fi

		local url="https://github.com/${repo}"
		/usr/local/bin/appiget install "$url" --noninteractive ||
			echo "  WARNING: Failed to install ${app}" >&2
	done
	echo "  Installed $# AppImage(s)."
}

# Run based on mode
case "$MODE" in
pre) reconcile_appimage_pre ;;
post) reconcile_appimage_post ;;
esac
