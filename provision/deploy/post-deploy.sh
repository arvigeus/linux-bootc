#!/usr/bin/env bash
## Post-deploy runner: executes all *.sh scripts in this directory.
##
## bootc: skips if the current image has already been processed.
## baremetal: runs unconditionally.
set -euo pipefail

DEPLOY_DIR="$(dirname "$0")"

_run_scripts() {
    for script in "$DEPLOY_DIR"/*.sh; do
        [[ "$script" == "$0" ]] && continue
        [[ -x "$script" ]] || continue
        echo ":: Running post-deploy: ${script##*/}"
        "$script"
    done
}

if command -v bootc &>/dev/null; then
    STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/post-deploy"
    STATE_FILE="$STATE_DIR/image-id"
    IMAGE_ID=$(bootc status --json | jq -r '.status.booted.image.imageDigest')
    if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "$IMAGE_ID" ]]; then
        exit 0
    fi
    _run_scripts
    mkdir -p "$STATE_DIR"
    echo "$IMAGE_ID" > "$STATE_FILE"
else
    _run_scripts
fi
