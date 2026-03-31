#!/usr/bin/env bash
## Flatpak app and remote reconciliation
##
## Pre-reconciliation:  clear preinstall.d, seed base.list if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra apps and remotes

FLATPAK_APPS_DIR="/usr/share/system-state.d/flatpak"
FLATPAK_REMOTES_LIST="${PKG_STATE_DIR}/flatpak-remotes.list"

reconcile_flatpak_pre() {
	echo "=== Flatpak Reconciliation (pre) ==="

	# Clear preinstall.d (build will re-declare everything)
	rm -rf /etc/flatpak/preinstall.d
	mkdir -p /etc/flatpak/preinstall.d

	if ! command -v flatpak &>/dev/null; then
		# Flatpak not installed yet — empty baseline means all future apps are managed
		echo "Flatpak not available. Creating empty baseline."
		mkdir -p "$PKG_STATE_DIR"
		touch "${PKG_STATE_DIR}/flatpak.base.list"
		return 0
	fi

	local installed_sorted
	installed_sorted=$(flatpak list --app --columns=application 2>/dev/null | sort -u)
	seed_base_list "${PKG_STATE_DIR}/flatpak.base.list" "$installed_sorted" "flatpak apps"
}

reconcile_flatpak_post() {
	echo "=== Flatpak Reconciliation (post) ==="

	if ! command -v flatpak &>/dev/null; then
		echo "Flatpak not available — skipping."
		return 0
	fi

	local installed_sorted
	installed_sorted=$(flatpak list --app --columns=application 2>/dev/null | sort -u)

	reconcile_post \
		"${PKG_STATE_DIR}/flatpak.list" \
		"${PKG_STATE_DIR}/flatpak.base.list" \
		"$installed_sorted" \
		"Flatpak apps"

	# Reconcile remotes
	_reconcile_flatpak_remotes
}

_reconcile_flatpak_remotes() {
	echo "=== Flatpak Remote Reconciliation ==="

	if [[ ! -f "$FLATPAK_REMOTES_LIST" ]]; then
		echo "No remote state found — skipping."
		return 0
	fi

	local -a declared_remotes=()
	mapfile -t declared_remotes <"$FLATPAK_REMOTES_LIST"
	filter_empty declared_remotes

	if [[ ${#declared_remotes[@]} -eq 0 ]]; then
		echo "No declared remotes."
		return 0
	fi

	local -a installed_remotes=()
	mapfile -t installed_remotes < <(flatpak remotes --columns=name 2>/dev/null)
	filter_empty installed_remotes

	local -a missing=()
	for remote in "${declared_remotes[@]}"; do
		local found=false
		for installed in "${installed_remotes[@]}"; do
			if [[ "$remote" == "$installed" ]]; then
				found=true
				break
			fi
		done
		$found || missing+=("$remote")
	done

	if [[ ${#missing[@]} -eq 0 ]]; then
		echo "All declared flatpak remotes are present."
		return 0
	fi

	echo "Missing remotes:"
	printf "  - %s\n" "${missing[@]}"
	echo ""
	echo "  [r] Restore them"
	echo "  [i] Ignore"
	read -rp "Choice: " ans
	case "$ans" in
	[Rr])
		for remote in "${missing[@]}"; do
			flatpak remote-add --if-not-exists "$remote" \
				"https://dl.flathub.org/repo/${remote}.flatpakrepo" 2>/dev/null ||
				echo "  WARNING: Could not restore remote '$remote'" >&2
		done
		echo "  Remotes restored."
		;;
	*)
		echo "  Ignored."
		;;
	esac
}

# Flatpak-specific implementations for common.sh callbacks
_remove_extra_packages() {
	for pkg in "$@"; do
		flatpak uninstall --noninteractive "$pkg" 2>/dev/null || true
	done
	echo "  Removed $# app(s)."
}

_install_missing_packages() {
	for pkg in "$@"; do
		# Look up remote from preinstall state
		local remote="flathub"
		if [[ -f "${FLATPAK_APPS_DIR}/${pkg}/.remote" ]]; then
			remote=$(cat "${FLATPAK_APPS_DIR}/${pkg}/.remote")
			[[ -n "$remote" ]] || remote="flathub"
		fi
		flatpak install --noninteractive "$remote" "$pkg" 2>/dev/null ||
			echo "  WARNING: Failed to install $pkg" >&2
	done
	echo "  Installed $# app(s)."
}

# Run based on mode
case "$MODE" in
pre) reconcile_flatpak_pre ;;
post) reconcile_flatpak_post ;;
esac
