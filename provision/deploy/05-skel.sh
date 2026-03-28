#!/usr/bin/env bash
## Post-deploy: sync /etc/skel into the user's home directory
##
## During container builds, modules write user config to /etc/skel/ (via $HOME).
## This script copies those files into the real home directory:
##   - New files: copied directly
##   - Changed files: existing version moved to .bak, then overwritten
##   - Identical files: skipped
set -euo pipefail

SKEL="/etc/skel"
[[ -d "$SKEL" ]] || exit 0

while IFS= read -r -d '' src; do
    rel="${src#"$SKEL"/}"
    dest="${HOME}/${rel}"

    if [[ -d "$src" ]]; then
        mkdir -p "$dest"
        continue
    fi

    if [[ -f "$dest" ]]; then
        cmp -s "$src" "$dest" && continue   # identical — skip
        mv "$dest" "${dest}.bak"            # differs — backup existing
    else
        mkdir -p "$(dirname "$dest")"
    fi

    cp "$src" "$dest"
done < <(find "$SKEL" -mindepth 1 -not -name '.' -print0 2>/dev/null)
