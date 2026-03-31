#!/usr/bin/env bash
## Post-deploy: install VS Code extensions and merge settings
##
## Reads state files written by the vscode build module:
##   /usr/share/system-state.d/vscode/config          — shell vars (CODE_CONF_DIR)
##   /usr/share/system-state.d/vscode/extensions.list  — one extension ID per line
##   /usr/share/system-state.d/vscode/settings.json    — merged settings
set -euo pipefail

VSCODE_STATE_DIR="/usr/share/system-state.d/vscode"

# Gracefully exit if state files don't exist yet
if [[ ! -d "$VSCODE_STATE_DIR" ]]; then
    exit 0
fi

# Source config (provides CODE_CONF_DIR and any future options)
if [[ -f "${VSCODE_STATE_DIR}/config" ]]; then
    # shellcheck source=/dev/null
    source "${VSCODE_STATE_DIR}/config"
fi
CODE_CONF_DIR="${CODE_CONF_DIR:-Code}"

# Merge settings
if [[ -f "${VSCODE_STATE_DIR}/settings.json" ]]; then
    SETTINGS_DIR="$HOME/.config/${CODE_CONF_DIR}/User"
    mkdir -p "$SETTINGS_DIR"
    SETTINGS_FILE="$SETTINGS_DIR/settings.json"

    if [[ -f "$SETTINGS_FILE" ]]; then
        jq -s '.[0] * .[1]' "$SETTINGS_FILE" "${VSCODE_STATE_DIR}/settings.json" > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
        cp "${VSCODE_STATE_DIR}/settings.json" "$SETTINGS_FILE"
    fi
fi

# Install extensions
if [[ -f "${VSCODE_STATE_DIR}/extensions.list" ]]; then
    while IFS= read -r ext; do
        [[ -n "$ext" ]] || continue
        code --install-extension "$ext"
    done < "${VSCODE_STATE_DIR}/extensions.list"
fi
