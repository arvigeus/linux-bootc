#!/usr/bin/env bash
## Reconciliation orchestrator
##
## Ensures the system matches the declared state in /usr/share/system-state.d/.
##
## Usage:
##   sudo bash scripts/reconciliation/reconcile.sh pre   — run before bootstrap
##   sudo bash scripts/reconciliation/reconcile.sh post  — run after bootstrap
##
## Pre-reconciliation:
##   - Files: detect drift, restore originals from .bak, clear state
##   - Packages: seed base.list from installed packages if missing
##
## Post-reconciliation:
##   - Files: verify build results match declared state, flag drift
##   - Packages: promote base→managed, clean stale base entries,
##     flag missing managed packages, flag untracked installed packages
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
STATE_DIR="/usr/share/system-state.d"

MODE="${1:-}"
if [[ "$MODE" != "pre" && "$MODE" != "post" ]]; then
	echo "Usage: reconcile.sh <pre|post>" >&2
	exit 1
fi

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Auto detect
source "$(dirname "$0")/../../provision/lib/detect.sh"
source "$(dirname "$0")/../../provision/lib/sudo.sh"

# --- Files ---
source "${SCRIPT_DIR}/files.sh"
if [[ "$MODE" == "pre" ]]; then
	reconcile_files_pre
else
	reconcile_files_post
fi

# --- Packages ---
source "${SCRIPT_DIR}/packages/common.sh"
if [[ ! -f "${SCRIPT_DIR}/packages/${PACKAGE_MANAGER}.sh" ]]; then
	echo "ERROR: No reconciliation script for package manager '${PACKAGE_MANAGER}'" >&2
	exit 1
fi
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/packages/${PACKAGE_MANAGER}.sh"

# --- Systemd services ---
source "${SCRIPT_DIR}/systemd.sh"

# --- Flatpak ---
if command -v flatpak &>/dev/null; then
	source "${SCRIPT_DIR}/flatpak.sh"
fi

# --- AppImages ---
if [[ -f /usr/local/bin/appiget ]]; then
	source "${SCRIPT_DIR}/packages/appimage.sh"
fi

# --- VS Code extensions ---
if command -v code &>/dev/null; then
	source "${SCRIPT_DIR}/packages/vscode.sh"
fi

echo ""
echo "Reconciliation ($MODE) complete."
