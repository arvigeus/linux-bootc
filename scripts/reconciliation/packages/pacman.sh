#!/usr/bin/env bash
## Pacman + Paru (AUR) package reconciliation
##
## Pre-reconciliation:  seed base lists if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra
##
## Native packages → pacman.list / pacman.base.list
## AUR packages    → paru.list   / paru.base.list

reconcile_pacman_packages_pre() {
    local pacman_base="${PKG_STATE_DIR}/pacman.base.list"
    local paru_base="${PKG_STATE_DIR}/paru.base.list"

    echo "=== Pacman Package Reconciliation (pre) ==="

    local need_seed=false
    [[ ! -f "$pacman_base" ]] && need_seed=true
    [[ ! -f "$paru_base" ]] && need_seed=true

    if ! $need_seed; then
        echo "Base state exists — nothing to do."
        return 0
    fi

    mkdir -p "$PKG_STATE_DIR"

    # Query current system
    local all_explicit foreign_only native_installed
    all_explicit=$(/usr/bin/pacman -Qqe 2>/dev/null | sort -u)
    foreign_only=$(/usr/bin/pacman -Qqem 2>/dev/null | sort -u)
    native_installed=$(comm -23 <(echo "$all_explicit") <(echo "$foreign_only"))

    # Seed pacman base
    if [[ ! -f "$pacman_base" ]]; then
        echo "Seeding pacman base from currently installed native packages..."
        echo "$native_installed" > "$pacman_base"
        echo "  Seeded $(wc -l < "$pacman_base") packages into pacman.base.list"
    fi

    # Seed paru base
    if [[ ! -f "$paru_base" ]]; then
        if [[ -n "$foreign_only" ]]; then
            echo "Seeding paru base from currently installed AUR packages..."
            echo "$foreign_only" > "$paru_base"
            echo "  Seeded $(wc -l < "$paru_base") packages into paru.base.list"
        else
            touch "$paru_base"
        fi
    fi
}

reconcile_pacman_packages_post() {
    local pacman_list="${PKG_STATE_DIR}/pacman.list"
    local pacman_base="${PKG_STATE_DIR}/pacman.base.list"
    local paru_list="${PKG_STATE_DIR}/paru.list"
    local paru_base="${PKG_STATE_DIR}/paru.base.list"

    echo "=== Pacman Package Reconciliation (post) ==="

    # Safety: base lists should exist from pre-reconciliation
    for f in "$pacman_base" "$paru_base"; do
        if [[ ! -f "$f" ]]; then
            echo "WARNING: $(basename "$f") missing — creating empty file."
            mkdir -p "$PKG_STATE_DIR"
            touch "$f"
        fi
    done

    # Query current system
    local all_explicit foreign_only native_installed
    all_explicit=$(/usr/bin/pacman -Qqe 2>/dev/null | sort -u)
    foreign_only=$(/usr/bin/pacman -Qqem 2>/dev/null | sort -u)
    native_installed=$(comm -23 <(echo "$all_explicit") <(echo "$foreign_only"))

    # Promote: managed packages out of base lists
    _promote_from_base "$pacman_list" "$pacman_base"
    _promote_from_base "$paru_list" "$paru_base"

    # Self-clean: remove uninstalled packages from base lists
    clean_base_list "$pacman_base" "$native_installed"
    clean_base_list "$paru_base" "$foreign_only"

    # --- Native packages ---
    local -a pacman_managed=() pacman_baseline=()
    [[ -f "$pacman_list" ]] && mapfile -t pacman_managed < "$pacman_list"
    mapfile -t pacman_baseline < "$pacman_base"
    filter_empty pacman_managed
    filter_empty pacman_baseline

    local native_expected
    native_expected=$(printf '%s\n' \
        "${pacman_baseline[@]+"${pacman_baseline[@]}"}" \
        "${pacman_managed[@]+"${pacman_managed[@]}"}" \
        | sort -u)

    # --- AUR packages ---
    local -a paru_managed=() paru_baseline=()
    [[ -f "$paru_list" ]] && mapfile -t paru_managed < "$paru_list"
    mapfile -t paru_baseline < "$paru_base"
    filter_empty paru_managed
    filter_empty paru_baseline

    local foreign_expected
    foreign_expected=$(printf '%s\n' \
        "${paru_baseline[@]+"${paru_baseline[@]}"}" \
        "${paru_managed[@]+"${paru_managed[@]}"}" \
        | sort -u)

    # --- Diff ---
    local -a extra_native=() extra_foreign=()
    mapfile -t extra_native < <(diff_lines "$native_installed" "$native_expected")
    mapfile -t extra_foreign < <(diff_lines "$foreign_only" "$foreign_expected")
    filter_empty extra_native
    filter_empty extra_foreign

    # Missing managed (only from .list, not base — base self-cleans silently)
    local -a missing_native_managed=() missing_foreign_managed=()
    if [[ ${#pacman_managed[@]} -gt 0 ]]; then
        local managed_sorted
        managed_sorted=$(printf '%s\n' "${pacman_managed[@]}" | sort -u)
        mapfile -t missing_native_managed < <(diff_lines "$managed_sorted" "$native_installed")
        filter_empty missing_native_managed
    fi
    if [[ ${#paru_managed[@]} -gt 0 ]]; then
        local managed_sorted
        managed_sorted=$(printf '%s\n' "${paru_managed[@]}" | sort -u)
        mapfile -t missing_foreign_managed < <(diff_lines "$managed_sorted" "$foreign_only")
        filter_empty missing_foreign_managed
    fi

    # --- Report and act ---
    local has_drift=false
    [[ ${#missing_native_managed[@]} -gt 0 || ${#missing_foreign_managed[@]} -gt 0 ]] && has_drift=true
    [[ ${#extra_native[@]} -gt 0 || ${#extra_foreign[@]} -gt 0 ]] && has_drift=true

    if ! $has_drift; then
        echo "Pacman packages match declared state."
        return 0
    fi

    [[ ${#missing_native_managed[@]} -gt 0 ]] && handle_missing_managed "${missing_native_managed[@]}"
    [[ ${#missing_foreign_managed[@]} -gt 0 ]] && handle_missing_managed "${missing_foreign_managed[@]}"
    [[ ${#extra_native[@]} -gt 0 ]] && handle_extra_packages "$pacman_base" "${extra_native[@]}"
    [[ ${#extra_foreign[@]} -gt 0 ]] && handle_extra_packages "$paru_base" "${extra_foreign[@]}"
}

# Helper: remove managed packages from base list (promotion)
_promote_from_base() {
    local list_file="$1" base_file="$2"
    [[ -f "$list_file" && -f "$base_file" ]] || return 0
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        if grep -qxF "$pkg" "$base_file"; then
            grep -vxF "$pkg" "$base_file" > "${base_file}.tmp" || true
            mv "${base_file}.tmp" "$base_file"
        fi
    done < "$list_file"
}

# Implementation of remove/install for pacman
_remove_extra_packages() {
    /usr/bin/pacman -Rns --noconfirm "$@"
    echo "  Removed $# package(s)."
}

_install_missing_packages() {
    # Separate native from AUR
    local -a native=() aur=()
    for pkg in "$@"; do
        if /usr/bin/pacman -Si "$pkg" &>/dev/null; then
            native+=("$pkg")
        else
            aur+=("$pkg")
        fi
    done
    [[ ${#native[@]} -gt 0 ]] && /usr/bin/pacman -S --noconfirm --needed "${native[@]}"
    [[ ${#aur[@]} -gt 0 ]] && /usr/bin/paru -S --noconfirm --needed "${aur[@]}"
    echo "  Installed $# package(s)."
}

# Run based on mode
case "$MODE" in
    pre)  reconcile_pacman_packages_pre ;;
    post) reconcile_pacman_packages_post ;;
esac
