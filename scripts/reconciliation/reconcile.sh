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
##   - Configs: copy to state if missing, merge if drifted
##   - Packages: seed base.list from installed packages if missing
##
## Post-reconciliation:
##   - Configs: same as pre (safety net — should already match)
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

# Detect package manager
if command -v dnf &>/dev/null; then
    PM=dnf
elif command -v pacman &>/dev/null; then
    PM=pacman
else
    echo "ERROR: No supported package manager found" >&2
    exit 1
fi

# --- Files ---
source "${SCRIPT_DIR}/files.sh"
reconcile_files

# --- Packages ---
source "${SCRIPT_DIR}/packages/common.sh"
case "$PM" in
    dnf)    source "${SCRIPT_DIR}/packages/dnf.sh" ;;
    pacman) source "${SCRIPT_DIR}/packages/pacman.sh" ;;
esac

echo ""
echo "Reconciliation ($MODE) complete."
