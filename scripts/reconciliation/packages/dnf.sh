#!/usr/bin/env bash
## DNF package and repo reconciliation
##
## Pre-reconciliation:  seed base.list if missing
## Post-reconciliation: promote, clean stale base, flag missing/extra

reconcile_dnf_packages_pre() {
    echo "=== DNF Package Reconciliation (pre) ==="

    local installed_sorted
    installed_sorted=$(/usr/bin/dnf repoquery --userinstalled --qf '%{name}' 2>/dev/null | sort -u)
    seed_base_list "${PKG_STATE_DIR}/dnf.base.list" "$installed_sorted" "packages"
}

reconcile_dnf_packages_post() {
    local list_file="${PKG_STATE_DIR}/dnf.list"
    local base_file="${PKG_STATE_DIR}/dnf.base.list"

    echo "=== DNF Package Reconciliation (post) ==="

    # Query currently installed
    local installed_sorted
    installed_sorted=$(/usr/bin/dnf repoquery --userinstalled --qf '%{name}' 2>/dev/null | sort -u)

    # Expand dnf groups into a temporary managed list (groups are dnf-specific)
    local effective_list="$list_file"
    if [[ -f "$list_file" ]] && grep -q '^@' "$list_file"; then
        effective_list=$(mktemp)
        # Copy non-group entries
        grep -v '^@' "$list_file" >> "$effective_list" || true
        # Expand groups into member packages
        while IFS= read -r line; do
            [[ "$line" == @* ]] || continue
            local group_name="${line#@}"
            /usr/bin/dnf group info "$group_name" 2>/dev/null \
                | sed -n '/^ /s/^ *//p' >> "$effective_list" || true
        done < "$list_file"
    fi

    reconcile_post "$effective_list" "$base_file" "$installed_sorted" "DNF packages"

    [[ "$effective_list" != "$list_file" ]] && rm -f "$effective_list"
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
