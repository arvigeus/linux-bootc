#!/usr/bin/env bash
## GearLever build-time shim
##
## Shadows the `gearlever` alias as a bash function. Handles dual-mode operation:
##
##   gearlever --integrate --yes <appimage>  — container: record state only;
##                                              baremetal: integrate + record
##
## Other subcommands pass through to the real gearlever.
##
## State format — one INI file per app:
##   /usr/share/system-state.d/appimage/<app-id>.ini
##
##   [appimage]
##   url=<download-url>
##   repo=<owner/repo>        (optional, for GitHub auto-update)
##   pattern=<asset-pattern>  (optional, for GitHub auto-update)
##
## Managed list is implicit: every .ini file = a managed app.
## Baseline is stored in appimage.base.list (app-id names only).

APPIMAGE_STATE_DIR="/usr/share/system-state.d/appimage"

gearlever() {
	case "${1:-}" in
	--integrate) _gearlever_shim_integrate "$@" ;;
	*)
		if [[ "$IS_CONTAINER" == true ]]; then
			return 0
		fi
		/usr/bin/flatpak run it.mijorus.gearlever "$@"
		;;
	esac
}

# gearlever --integrate --yes <appimage-path> [--url <url>] [--repo <owner/repo>] [--pattern <pattern>]
# Container: record INI for post-deploy
# Baremetal: integrate + record state
_gearlever_shim_integrate() {
	local appimage="" url="" repo="" pattern=""
	local -a passthrough=()

	for arg in "$@"; do
		case "$arg" in
		--integrate | --yes) passthrough+=("$arg") ;;
		--url=*) url="${arg#--url=}" ;;
		--repo=*) repo="${arg#--repo=}" ;;
		--pattern=*) pattern="${arg#--pattern=}" ;;
		*)
			appimage="$arg"
			passthrough+=("$arg")
			;;
		esac
	done

	if [[ -z "$appimage" ]]; then
		echo "ERROR: gearlever shim: no AppImage path provided" >&2
		echo "  Usage: gearlever --integrate --yes <appimage>" >&2
		return 1
	fi

	local app_id
	app_id=$(appimage_app_id "$appimage")

	# Record state (always, both container and baremetal)
	mkdir -p "$APPIMAGE_STATE_DIR"
	cat >"${APPIMAGE_STATE_DIR}/${app_id}.ini" <<EOF
[appimage]
url=${url}
repo=${repo}
pattern=${pattern}
EOF

	if [[ "$IS_CONTAINER" == true ]]; then
		echo ":: Registered AppImage: ${app_id}"
		return 0
	fi

	# Baremetal: actually integrate (pass only real gearlever args)
	run_unprivileged /usr/bin/flatpak run it.mijorus.gearlever "${passthrough[@]}" || return $?

	# Set up auto-update if repo is known
	if [[ -n "$repo" ]]; then
		local appimage_path
		appimage_path=$(run_unprivileged /usr/bin/flatpak run it.mijorus.gearlever --list-installed \
			2>/dev/null | grep -oP '/\S+\.[aA]pp[iI]mage$' | head -n 1)
		if [[ -n "$appimage_path" ]]; then
			run_unprivileged /usr/bin/flatpak run it.mijorus.gearlever \
				--set-update-source "$appimage_path" --manager github "repo=${repo}" || true
		fi
	fi

	echo ":: Integrated AppImage: ${app_id}"
}

# Called once at build start — wipes managed INI files for a clean rebuild,
# preserves base.list.
gearlever_shim_reset() {
	[[ "$IS_CONTAINER" == true ]] && return 0
	rm -f "${APPIMAGE_STATE_DIR}"/*.ini
}
