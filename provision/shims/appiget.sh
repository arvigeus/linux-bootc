#!/usr/bin/env bash
## appiget build-time shim
##
## Thin wrapper around the appiget CLI that records state for reconciliation.
## appiget handles all the heavy lifting; the shim just tracks what was installed.
##
## State recorded for reconciliation:
##   /usr/share/system-state.d/appimage/<app-id>.ini
##
##   [appimage]
##   repo=<owner/repo-or-url>

APPIMAGE_STATE_DIR="/usr/share/system-state.d/appimage"

appiget() {
	case "${1:-}" in
	install) _appiget_shim_install "$@" ;;
	*)
		# Other commands pass through directly
		/usr/local/bin/appiget "$@"
		;;
	esac
}

# appiget install <github-url> [--pattern <pattern>] [--name <app-id>] --noninteractive
# Installs via appiget, then records metadata for reconciliation
_appiget_shim_install() {
	local url=""
	local app_id=""
	local -a required=(--noninteractive)
	local -a found_required=()
	local -a args=("$@")

	# Parse arguments: extract URL, app-id (--name), and verify required flags
	local skip_next=false
	for arg in "${args[@]}"; do
		if $skip_next; then
			skip_next=false
			continue
		fi

		case "$arg" in
		--install) ;; # skip command
		--noninteractive)
			found_required+=(--noninteractive)
			;;
		--pattern) skip_next=true ;;
		--name)
			app_id="${args[$((${args[@]/%$arg*/} | wc - w))]}"
			;;
		*)
			if [[ -z "$url" && "$arg" != install ]]; then
				url="$arg"
			fi
			;;
		esac
	done

	# Validate required URL
	[[ -n "$url" ]] || {
		echo "ERROR: appiget shim: URL required" >&2
		return 1
	}

	# Validate all required flags are present
	for req in "${required[@]}"; do
		if ! printf '%s\n' "${found_required[@]}" | grep -q "^${req}$"; then
			echo "ERROR: appiget shim: $req is required" >&2
			return 1
		fi
	done

	# Install via appiget
	/usr/local/bin/appiget install "${args[@]}" || return $?

	# Record state for reconciliation (baremetal only)
	# Containers always start from a clean image, no need to track state
	[[ "$IS_CONTAINER" == true ]] && return 0

	# If --name was provided, use that; otherwise query appiget list
	if [[ -z "$app_id" ]]; then
		# Extract repo from URL for querying
		local repo
		repo=$(echo "$url" | sed -E 's|https?://github\.com/||; s/\.git$//')
		app_id=$(/usr/local/bin/appiget list 2>/dev/null | awk -v repo="$repo" '$3 == repo {print $1; exit}')
	fi

	if [[ -n "$app_id" ]]; then
		mkdir -p "$APPIMAGE_STATE_DIR"
		cat >"${APPIMAGE_STATE_DIR}/${app_id}.ini" <<EOF
[appimage]
repo=${url}
EOF
	fi
}

# Called once at build start — wipes managed INI files for a clean rebuild
appiget_shim_reset() {
	rm -f "${APPIMAGE_STATE_DIR}"/*.ini
}
