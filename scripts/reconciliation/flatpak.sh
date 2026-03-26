#!/usr/bin/env bash
## Flatpak app and remote reconciliation
##
## Pre-reconciliation:  clear preinstall.d, seed base.list if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra apps and remotes

FLATPAK_APPS_DIR="/usr/share/system-state.d/flatpak"
FLATPAK_REMOTES_LIST="${PKG_STATE_DIR}/flatpak-remotes.list"

reconcile_flatpak_pre() {
    echo "=== Flatpak Reconciliation (pre) ==="

    # Clear preinstall.d (build will re-declare everything)
    rm -rf /etc/flatpak/preinstall.d
    mkdir -p /etc/flatpak/preinstall.d

    local base_file="${PKG_STATE_DIR}/flatpak.base.list"

    if [[ -f "$base_file" ]]; then
        echo "Base state exists — nothing to do."
        return 0
    fi

    mkdir -p "$PKG_STATE_DIR"

    if ! command -v flatpak &>/dev/null; then
        # Flatpak not installed yet — empty baseline means all future apps are managed
        echo "Flatpak not available. Creating empty baseline."
        touch "$base_file"
        return 0
    fi

    # Seed base.list from currently installed apps
    echo "Seeding flatpak base from currently installed apps..."
    flatpak list --app --columns=application 2>/dev/null | sort -u > "$base_file"
    echo "  Seeded $(wc -l < "$base_file") apps into flatpak.base.list"
}

reconcile_flatpak_post() {
    local list_file="${PKG_STATE_DIR}/flatpak.list"
    local base_file="${PKG_STATE_DIR}/flatpak.base.list"

    echo "=== Flatpak Reconciliation (post) ==="

    # Safety: base.list should exist from pre-reconciliation
    if [[ ! -f "$base_file" ]]; then
        echo "WARNING: flatpak.base.list missing — creating empty file."
        mkdir -p "$PKG_STATE_DIR"
        touch "$base_file"
    fi

    if ! command -v flatpak &>/dev/null; then
        echo "Flatpak not available — skipping."
        return 0
    fi

    # Query currently installed apps
    local installed_sorted
    installed_sorted=$(flatpak list --app --columns=application 2>/dev/null | sort -u)

    # Promote: managed packages out of base list
    if [[ -f "$list_file" ]]; then
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] || continue
            if grep -qxF "$pkg" "$base_file"; then
                grep -vxF "$pkg" "$base_file" > "${base_file}.tmp" || true
                mv "${base_file}.tmp" "$base_file"
            fi
        done < "$list_file"
    fi

    # Self-clean: remove uninstalled apps from base.list
    clean_base_list "$base_file" "$installed_sorted"

    # Build expected state = base ∪ managed
    local -a managed_pkgs=()
    if [[ -f "$list_file" ]]; then
        mapfile -t managed_pkgs < "$list_file"
    fi
    local -a base_pkgs=()
    mapfile -t base_pkgs < "$base_file"
    filter_empty managed_pkgs
    filter_empty base_pkgs

    local expected_sorted
    expected_sorted=$(printf '%s\n' \
        "${base_pkgs[@]+"${base_pkgs[@]}"}" \
        "${managed_pkgs[@]+"${managed_pkgs[@]}"}" \
        | sort -u)

    # Diff
    local -a missing_managed=() extra=()
    mapfile -t extra < <(diff_lines "$installed_sorted" "$expected_sorted")
    filter_empty extra

    if [[ ${#managed_pkgs[@]} -gt 0 ]]; then
        local managed_sorted
        managed_sorted=$(printf '%s\n' "${managed_pkgs[@]}" | sort -u)
        mapfile -t missing_managed < <(diff_lines "$managed_sorted" "$installed_sorted")
        filter_empty missing_managed
    fi

    # Report and act
    local has_drift=false
    [[ ${#missing_managed[@]} -gt 0 || ${#extra[@]} -gt 0 ]] && has_drift=true

    if ! $has_drift; then
        echo "Flatpak apps match declared state."
    else
        [[ ${#missing_managed[@]} -gt 0 ]] && handle_missing_managed "${missing_managed[@]}"
        [[ ${#extra[@]} -gt 0 ]] && handle_extra_packages "$base_file" "${extra[@]}"
    fi

    # Reconcile remotes
    _reconcile_flatpak_remotes
}

_reconcile_flatpak_remotes() {
    echo "=== Flatpak Remote Reconciliation ==="

    if [[ ! -f "$FLATPAK_REMOTES_LIST" ]]; then
        echo "No remote state found — skipping."
        return 0
    fi

    local -a declared_remotes=()
    mapfile -t declared_remotes < "$FLATPAK_REMOTES_LIST"
    filter_empty declared_remotes

    if [[ ${#declared_remotes[@]} -eq 0 ]]; then
        echo "No declared remotes."
        return 0
    fi

    local -a installed_remotes=()
    mapfile -t installed_remotes < <(flatpak remotes --columns=name 2>/dev/null)
    filter_empty installed_remotes

    local -a missing=()
    for remote in "${declared_remotes[@]}"; do
        local found=false
        for installed in "${installed_remotes[@]}"; do
            if [[ "$remote" == "$installed" ]]; then
                found=true
                break
            fi
        done
        $found || missing+=("$remote")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "All declared flatpak remotes are present."
        return 0
    fi

    echo "Missing remotes:"
    printf "  - %s\n" "${missing[@]}"
    echo ""
    echo "  [r] Restore them"
    echo "  [i] Ignore"
    read -rp "Choice: " ans
    case "$ans" in
        [Rr])
            for remote in "${missing[@]}"; do
                flatpak remote-add --if-not-exists "$remote" \
                    "https://dl.flathub.org/repo/${remote}.flatpakrepo" 2>/dev/null || \
                    echo "  WARNING: Could not restore remote '$remote'" >&2
            done
            echo "  Remotes restored."
            ;;
        *)
            echo "  Ignored."
            ;;
    esac
}

# Flatpak-specific implementations for common.sh callbacks
_remove_extra_packages() {
    for pkg in "$@"; do
        flatpak uninstall --noninteractive "$pkg" 2>/dev/null || true
    done
    echo "  Removed $# app(s)."
}

_install_missing_packages() {
    for pkg in "$@"; do
        # Look up remote from preinstall state
        local remote="flathub"
        if [[ -f "${FLATPAK_APPS_DIR}/${pkg}/.remote" ]]; then
            remote=$(cat "${FLATPAK_APPS_DIR}/${pkg}/.remote")
            [[ -n "$remote" ]] || remote="flathub"
        fi
        flatpak install --noninteractive "$remote" "$pkg" 2>/dev/null || \
            echo "  WARNING: Failed to install $pkg" >&2
    done
    echo "  Installed $# app(s)."
}

# Run based on mode
case "$MODE" in
    pre)  reconcile_flatpak_pre ;;
    post) reconcile_flatpak_post ;;
esac
