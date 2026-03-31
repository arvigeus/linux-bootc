#!/usr/bin/env bash
## VS Code build-time shim
##
## Shadows the `code` command as a bash function. Handles dual-mode operation:
##
##   code --install-extension <id>  — container: record only;
##                                     baremetal: install (unprivileged) + record
##
## Other subcommands pass through to /usr/bin/code.
##
## Generated files:
##   /usr/share/system-state.d/vscode/extensions.list      — managed extensions (one per line)
##   /usr/share/system-state.d/vscode/extensions.base.list — unmanaged baseline extensions

VSCODE_STATE_DIR="/usr/share/system-state.d/vscode"

code() {
	case "${1:-}" in
	--install-extension) _vscode_shim_install_extension "$@" ;;
	*) run_unprivileged /usr/bin/code "$@" ;;
	esac
}

# code --install-extension <extension-id>
# Container: record to extensions.list
# Baremetal: install as user, then record on success
_vscode_shim_install_extension() {
	local ext_id="${2:-}"

	if [[ -z "$ext_id" ]]; then
		echo "ERROR: vscode shim: usage: code --install-extension <extension-id>" >&2
		return 1
	fi

	mkdir -p "$VSCODE_STATE_DIR"
	local list="${VSCODE_STATE_DIR}/extensions.list"

	if [[ "$IS_CONTAINER" == true ]]; then
		# Container: record only (no display server / user session)
		touch "$list"
		if ! grep -qxF "$ext_id" "$list" 2>/dev/null; then
			echo "$ext_id" >>"$list"
		fi
		echo ":: Registered VS Code extension: ${ext_id}"
		return 0
	fi

	# Baremetal: install first, record on success
	run_unprivileged /usr/bin/code --install-extension "$ext_id" || return $?

	touch "$list"
	if ! grep -qxF "$ext_id" "$list" 2>/dev/null; then
		echo "$ext_id" >>"$list"
	fi
	echo ":: Installed VS Code extension: ${ext_id}"
}

# Called once at build start — wipes managed list for a clean rebuild,
# preserves base.list.
vscode_shim_reset() {
	[[ "$IS_CONTAINER" == true ]] && return 0
	rm -f "${VSCODE_STATE_DIR}/extensions.list"
}
