#!/usr/bin/env bash
## DNF package and repo reconciliation
##
## Pre-reconciliation:  seed base.list if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra

reconcile_dnf_packages_pre() {
    local base_file="${PKG_STATE_DIR}/dnf.base.list"

    echo "=== DNF Package Reconciliation (pre) ==="

    if [[ -f "$base_file" ]]; then
        echo "Base state exists — nothing to do."
        return 0
    fi

    # Seed base.list from currently installed packages
    echo "No base state found. Seeding from currently installed packages..."
    mkdir -p "$PKG_STATE_DIR"

    local installed_sorted
    installed_sorted=$(/usr/bin/dnf repoquery --userinstalled --qf '%{name}' 2>/dev/null | sort -u)
    echo "$installed_sorted" > "$base_file"
    echo "  Seeded $(wc -l < "$base_file") packages into dnf.base.list"
}

reconcile_dnf_packages_post() {
    local list_file="${PKG_STATE_DIR}/dnf.list"
    local base_file="${PKG_STATE_DIR}/dnf.base.list"

    echo "=== DNF Package Reconciliation (post) ==="

    # Safety: base.list should exist from pre-reconciliation
    if [[ ! -f "$base_file" ]]; then
        echo "WARNING: base.list missing — creating empty file."
        mkdir -p "$PKG_STATE_DIR"
        touch "$base_file"
    fi

    # Query currently installed
    local installed_sorted
    installed_sorted=$(/usr/bin/dnf repoquery --userinstalled --qf '%{name}' 2>/dev/null | sort -u)

    # Promote: if a package is in both base and managed, remove from base
    if [[ -f "$list_file" ]]; then
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] || continue
            if grep -qxF "$pkg" "$base_file"; then
                grep -vxF "$pkg" "$base_file" > "${base_file}.tmp" || true
                mv "${base_file}.tmp" "$base_file"
            fi
        done < "$list_file"
    fi

    # Self-clean: remove uninstalled packages from base.list
    clean_base_list "$base_file" "$installed_sorted"

    # Build expected state = base ∪ managed
    local -a managed_pkgs=() managed_groups=()
    if [[ -f "$list_file" ]]; then
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            if [[ "$pkg" == @* ]]; then
                managed_groups+=("$pkg")
            else
                managed_pkgs+=("$pkg")
            fi
        done < "$list_file"
    fi

    # Expand dnf groups into member packages
    for group in "${managed_groups[@]+"${managed_groups[@]}"}"; do
        local group_name="${group#@}"
        local -a members=()
        mapfile -t members < <(/usr/bin/dnf group info "$group_name" 2>/dev/null \
            | sed -n '/^ /s/^ *//p' || true)
        managed_pkgs+=("${members[@]+"${members[@]}"}")
    done

    local -a base_pkgs=()
    mapfile -t base_pkgs < "$base_file"
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

    # Only flag missing from managed list (not base — base self-cleans silently)
    if [[ ${#managed_pkgs[@]} -gt 0 ]]; then
        local managed_sorted
        managed_sorted=$(printf '%s\n' "${managed_pkgs[@]}" | sort -u)
        local -a all_missing=()
        mapfile -t all_missing < <(diff_lines "$managed_sorted" "$installed_sorted")
        filter_empty all_missing
        missing_managed=("${all_missing[@]+"${all_missing[@]}"}")
    fi

    if [[ ${#missing_managed[@]} -eq 0 && ${#extra[@]} -eq 0 ]]; then
        echo "DNF packages match declared state."
        return 0
    fi

    [[ ${#missing_managed[@]} -gt 0 ]] && handle_missing_managed "${missing_managed[@]}"
    [[ ${#extra[@]} -gt 0 ]] && handle_extra_packages "$base_file" "${extra[@]}"
}

reconcile_dnf_repos() {
    local repos_list="${PKG_STATE_DIR}/repos.list"

    echo "=== DNF Repo Reconciliation ==="

    if [[ ! -f "$repos_list" ]]; then
        echo "No repo state found — skipping."
        return 0
    fi

    local -a missing_repos=()
    while IFS=$'\t' read -r type args; do
        [[ -z "$type" || "$type" == \#* ]] && continue
        case "$type" in
            dnf-copr)
                if ! /usr/bin/dnf copr list 2>/dev/null | grep -q "$args"; then
                    missing_repos+=("$args")
                fi
                ;;
        esac
    done < "$repos_list"

    if [[ ${#missing_repos[@]} -eq 0 ]]; then
        echo "All declared DNF repos are present."
        return 0
    fi

    echo "Missing repos:"
    printf "  - copr: %s\n" "${missing_repos[@]}"
    echo ""
    echo "  [r] Restore them"
    echo "  [i] Ignore"
    read -rp "Choice: " ans
    case "$ans" in
        [Rr])
            for copr_id in "${missing_repos[@]}"; do
                /usr/bin/dnf copr enable -y "$copr_id"
            done
            echo "  Repos restored."
            ;;
        *)
            echo "  Ignored."
            ;;
    esac
}

# Implementation of remove/install for dnf
_remove_extra_packages() {
    /usr/bin/dnf remove -y "$@"
    echo "  Removed $# package(s)."
}

_install_missing_packages() {
    /usr/bin/dnf install -y "$@"
    echo "  Installed $# package(s)."
}

# Run based on mode
case "$MODE" in
    pre)
        reconcile_dnf_packages_pre
        ;;
    post)
        reconcile_dnf_repos
        reconcile_dnf_packages_post
        ;;
esac
