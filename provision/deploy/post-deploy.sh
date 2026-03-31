#!/usr/bin/env bash
## Post-deploy runner: executes all *.sh scripts in this directory.
## Skips if the current image has already been processed.
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

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/post-deploy"
STATE_FILE="$STATE_DIR/image-id"
IMAGE_ID=$(bootc status --json | jq -r '.status.booted.image.imageDigest')
if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "$IMAGE_ID" ]]; then
	exit 0
fi
_run_scripts
mkdir -p "$STATE_DIR"
echo "$IMAGE_ID" >"$STATE_FILE"
