#!/usr/bin/env bash
## VS Code extension reconciliation
##
## Pre-reconciliation:  seed base.list if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra

VSCODE_STATE_DIR="/usr/share/system-state.d/vscode"

reconcile_vscode_pre() {
	echo "=== VS Code Extension Reconciliation (pre) ==="

	local installed_sorted
	installed_sorted=$(run_unprivileged code --list-extensions 2>/dev/null | sort -u)
	seed_base_list "${VSCODE_STATE_DIR}/extensions.base.list" "$installed_sorted" "extensions"
}

reconcile_vscode_post() {
	echo "=== VS Code Extension Reconciliation (post) ==="

	local installed_sorted
	installed_sorted=$(run_unprivileged code --list-extensions 2>/dev/null | sort -u)

	reconcile_post \
		"${VSCODE_STATE_DIR}/extensions.list" \
		"${VSCODE_STATE_DIR}/extensions.base.list" \
		"$installed_sorted" \
		"VS Code extensions"
}

# Implementation of remove/install for VS Code extensions
_remove_extra_packages() {
	for ext in "$@"; do
		run_unprivileged code --uninstall-extension "$ext" 2>/dev/null || true
	done
	echo "  Removed $# extension(s)."
}

_install_missing_packages() {
	for ext in "$@"; do
		run_unprivileged code --install-extension "$ext"
	done
	echo "  Installed $# extension(s)."
}

# Run based on mode
case "$MODE" in
pre) reconcile_vscode_pre ;;
post) reconcile_vscode_post ;;
esac
