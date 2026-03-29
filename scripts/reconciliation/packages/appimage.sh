#!/usr/bin/env bash
## AppImage reconciliation
##
## Pre-reconciliation:  seed base.list if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra
##
## Managed list is derived from .ini files in the state directory.
## Currently uses GearLever as the backend. If replaced, only the
## _appimage_list_installed, _remove_extra_packages, and _install_missing_packages
## functions need updating.

APPIMAGE_STATE_DIR="/usr/share/system-state.d/appimage"

_appimage_list_installed() {
    run_unprivileged flatpak run it.mijorus.gearlever --list-installed 2>/dev/null \
        | grep -oP '/\S+\.[aA]pp[iI]mage$' \
        | xargs -I{} basename {} \
        | sed 's/[-_][0-9].*//; s/\.[aA]pp[iI]mage$//i' \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u
}

# Build a managed list from .ini filenames
_appimage_managed_list() {
    local tmpfile
    tmpfile=$(mktemp)
    for ini in "$APPIMAGE_STATE_DIR"/*.ini; do
        [[ -f "$ini" ]] || continue
        basename "$ini" .ini
    done | sort -u > "$tmpfile"
    echo "$tmpfile"
}

reconcile_appimage_pre() {
    echo "=== AppImage Reconciliation (pre) ==="

    local installed_sorted
    installed_sorted=$(_appimage_list_installed)
    seed_base_list "${APPIMAGE_STATE_DIR}/appimage.base.list" "$installed_sorted" "AppImages"
}

reconcile_appimage_post() {
    echo "=== AppImage Reconciliation (post) ==="

    local installed_sorted
    installed_sorted=$(_appimage_list_installed)

    # Build a temporary managed list file from .ini files
    local managed_list
    managed_list=$(_appimage_managed_list)

    reconcile_post \
        "$managed_list" \
        "${APPIMAGE_STATE_DIR}/appimage.base.list" \
        "$installed_sorted" \
        "AppImages"

    rm -f "$managed_list"
}

# Implementation of remove/install for AppImages (via GearLever)
_remove_extra_packages() {
    for app in "$@"; do
        local path
        path=$(run_unprivileged flatpak run it.mijorus.gearlever --list-installed 2>/dev/null \
            | grep -i "$app" | grep -oP '/\S+\.[aA]pp[iI]mage$' | head -n 1)
        if [[ -n "$path" ]]; then
            run_unprivileged flatpak run it.mijorus.gearlever --remove --yes "$path" 2>/dev/null || true
        fi
    done
    echo "  Removed $# AppImage(s)."
}

_install_missing_packages() {
    for app in "$@"; do
        local ini="${APPIMAGE_STATE_DIR}/${app}.ini"
        if [[ ! -f "$ini" ]]; then
            echo "  WARNING: No INI for ${app} — skipping" >&2
            continue
        fi

        local repo pattern url
        repo=$(sed -n 's/^repo=//p' "$ini")
        pattern=$(sed -n 's/^pattern=//p' "$ini")
        url=$(sed -n 's/^url=//p' "$ini")

        # Re-resolve latest URL if possible
        if [[ -n "$repo" && -n "$pattern" ]]; then
            local fresh_url
            fresh_url=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" \
                | grep -o '"browser_download_url": "[^"]*"' \
                | cut -d'"' -f4 \
                | grep -E "$pattern" \
                | head -n 1)
            [[ -n "$fresh_url" ]] && url="$fresh_url"
        fi

        if [[ -z "$url" ]]; then
            echo "  WARNING: No download URL for ${app} — skipping" >&2
            continue
        fi

        local filename temp
        filename=$(basename "$url")
        temp="/tmp/${filename}"

        curl -L -o "$temp" "$url" && chmod +x "$temp" \
            && run_unprivileged flatpak run it.mijorus.gearlever --integrate --yes "$temp" \
            || echo "  WARNING: Failed to install ${app}" >&2

        # Set up auto-update
        if [[ -n "$repo" ]]; then
            local appimage_path
            appimage_path=$(run_unprivileged flatpak run it.mijorus.gearlever --list-installed \
                2>/dev/null | grep -i "$app" | grep -oP '/\S+\.[aA]pp[iI]mage$' | head -n 1)
            if [[ -n "$appimage_path" ]]; then
                run_unprivileged flatpak run it.mijorus.gearlever \
                    --set-update-source "$appimage_path" --manager github "repo=${repo}" || true
            fi
        fi

        rm -f "$temp"
    done
    echo "  Installed $# AppImage(s)."
}

# Run based on mode
case "$MODE" in
    pre)  reconcile_appimage_pre ;;
    post) reconcile_appimage_post ;;
esac
