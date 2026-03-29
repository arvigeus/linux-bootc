#!/usr/bin/env bash
## Post-deploy: install AppImages from recorded state (via GearLever)
##
## Reads INI files written at build time:
##   /usr/share/system-state.d/appimage/<app-id>.ini
##
## If repo+pattern are set, re-resolves the latest download URL at deploy time
## (the image may be days old). Falls back to the baked-in url.
set -euo pipefail

APPIMAGE_STATE_DIR="/usr/share/system-state.d/appimage"

if [[ ! -d "$APPIMAGE_STATE_DIR" ]]; then
    exit 0
fi

# Get list of already-integrated apps (for idempotency)
installed_apps=""
if flatpak run it.mijorus.gearlever --list-installed &>/dev/null; then
    installed_apps=$(flatpak run it.mijorus.gearlever --list-installed 2>/dev/null || true)
fi

_ini_get() {
    local file="$1" key="$2"
    sed -n "s/^${key}=//p" "$file"
}

for ini in "$APPIMAGE_STATE_DIR"/*.ini; do
    [[ -f "$ini" ]] || continue
    app_id=$(basename "$ini" .ini)

    # Skip if already integrated
    if echo "$installed_apps" | grep -qi "$app_id"; then
        continue
    fi

    repo=$(_ini_get "$ini" repo)
    pattern=$(_ini_get "$ini" pattern)
    url=$(_ini_get "$ini" url)

    # Re-resolve latest URL from GitHub if possible
    if [[ -n "$repo" && -n "$pattern" ]]; then
        fresh_url=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" \
            | grep -o '"browser_download_url": "[^"]*"' \
            | cut -d'"' -f4 \
            | grep -E "$pattern" \
            | head -n 1)
        [[ -n "$fresh_url" ]] && url="$fresh_url"
    fi

    if [[ -z "$url" ]]; then
        echo "WARNING: No download URL for ${app_id} — skipping" >&2
        continue
    fi

    filename=$(basename "$url")
    temp="/tmp/${filename}"

    echo ":: Installing AppImage: ${app_id}"
    if ! curl -L -o "$temp" "$url"; then
        echo "WARNING: Failed to download ${url}" >&2
        rm -f "$temp"
        continue
    fi
    chmod +x "$temp"

    if ! flatpak run it.mijorus.gearlever --integrate --yes "$temp"; then
        echo "WARNING: Failed to integrate ${app_id}" >&2
        rm -f "$temp"
        continue
    fi

    # Set up auto-update from GitHub if repo is known
    if [[ -n "$repo" ]]; then
        appimage_path=$(flatpak run it.mijorus.gearlever --list-installed \
            2>/dev/null | grep -oP '/\S+\.[aA]pp[iI]mage$' | head -n 1)
        if [[ -n "$appimage_path" ]]; then
            flatpak run it.mijorus.gearlever \
                --set-update-source "$appimage_path" --manager github "repo=${repo}" || true
        fi
    fi

    rm -f "$temp"
done
