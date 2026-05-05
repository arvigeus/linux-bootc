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
	install)
		shift
		_appiget_shim_install "$@"
		;;
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
	local found_noninteractive=false
	local -a args=("$@")
	local -a install_args=()

	# Parse arguments: extract URL, app-id (--name), and verify required flags.
	# --noninteractive is a global appiget flag and must be passed before the
	# subcommand, so we strip it from install_args and prepend it ourselves.
	# Use pre-increment (++i): post-increment ((i++)) returns the old value,
	# which is 0 on the first pass and trips `set -e`.
	local i=0
	while ((i < ${#args[@]})); do
		local arg="${args[i]}"
		case "$arg" in
		--noninteractive)
			found_noninteractive=true
			;;
		--pattern)
			install_args+=("$arg" "${args[i + 1]:-}")
			((++i))
			;;
		--name)
			((++i))
			app_id="${args[i]:-}"
			install_args+=(--name "$app_id")
			;;
		*)
			if [[ -z "$url" ]]; then
				url="$arg"
			fi
			install_args+=("$arg")
			;;
		esac
		((++i))
	done

	# Validate required URL
	[[ -n "$url" ]] || {
		echo "ERROR: appiget shim: URL required" >&2
		return 1
	}

	# Validate required flags
	$found_noninteractive || {
		echo "ERROR: appiget shim: --noninteractive is required" >&2
		return 1
	}

	# Install via appiget (--noninteractive is a global flag, must precede subcommand)
	/usr/local/bin/appiget --noninteractive install "${install_args[@]}" || return $?

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
