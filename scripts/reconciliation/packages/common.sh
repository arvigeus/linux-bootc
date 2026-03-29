#!/usr/bin/env bash
## Shared helpers for package reconciliation scripts
##
## Reconciliation model:
##   .list      — managed packages (owned by build-time shims, read-only here)
##   .base.list — baseline packages (known but unmanaged, self-cleaning)
##
##   | State          | Installed? | Action                              |
##   |----------------|------------|-------------------------------------|
##   | In .list       | Yes        | Nothing                             |
##   | In .list       | No         | Prompt: install or ignore           |
##   | In .base.list  | Yes        | Nothing                             |
##   | In .base.list  | No         | Silently remove from base.list      |
##   | In neither     | Yes        | Prompt: add to base, remove, ignore |

STATE_DIR="/usr/share/system-state.d"
# shellcheck disable=SC2034 # used by other scripts that source this file
PKG_STATE_DIR="${STATE_DIR}/packages"

# --- Low-level helpers ---

# Prints lines in $1 but not in $2 (both are sorted newline-separated strings).
diff_lines() {
    comm -23 <(echo "$1") <(echo "$2")
}

# Filter empty lines from an array via nameref.
filter_empty() {
    local -n _arr=$1
    local -a _clean=()
    for _item in "${_arr[@]+"${_arr[@]}"}"; do
        [[ -n "$_item" ]] && _clean+=("$_item")
    done
    _arr=("${_clean[@]+"${_clean[@]}"}")
}

# Silently remove uninstalled packages from a base.list file.
# Usage: clean_base_list <base_file> <installed_sorted>
clean_base_list() {
    local base_file="$1" installed_sorted="$2"
    [[ -f "$base_file" ]] || return 0

    local base_sorted
    base_sorted=$(sort -u "$base_file")

    # Keep only packages that are still installed
    local cleaned
    cleaned=$(comm -12 <(echo "$base_sorted") <(echo "$installed_sorted"))
    echo "$cleaned" > "$base_file"
}

# Remove managed packages from base list (promotion).
# Usage: promote_from_base <list_file> <base_file>
promote_from_base() {
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

# --- Pre-reconciliation ---

# Seed base.list from currently installed packages if missing.
# Usage: seed_base_list <base_file> <installed_sorted> <label>
seed_base_list() {
    local base_file="$1" installed_sorted="$2" label="$3"

    if [[ -f "$base_file" ]]; then
        return 0
    fi

    echo "No base state found. Seeding from currently installed ${label}..."
    mkdir -p "$(dirname "$base_file")"
    echo "$installed_sorted" > "$base_file"
    echo "  Seeded $(wc -l < "$base_file") ${label} into $(basename "$base_file")"
}

# --- Post-reconciliation ---

# Full post-reconciliation cycle: promote, clean, diff, report.
# Callers must define _remove_extra_packages() and _install_missing_packages()
# before calling this function.
#
# Usage: reconcile_post <list_file> <base_file> <installed_sorted> <label>
reconcile_post() {
    local list_file="$1" base_file="$2" installed_sorted="$3" label="$4"

    # Safety: base.list should exist from pre-reconciliation
    if [[ ! -f "$base_file" ]]; then
        echo "WARNING: $(basename "$base_file") missing — creating empty file."
        mkdir -p "$(dirname "$base_file")"
        touch "$base_file"
    fi

    # Promote managed out of base
    promote_from_base "$list_file" "$base_file"

    # Self-clean: remove uninstalled from base
    clean_base_list "$base_file" "$installed_sorted"

    # Read managed
    local -a managed=()
    if [[ -f "$list_file" ]]; then
        mapfile -t managed < "$list_file"
        filter_empty managed
    fi

    # Read base
    local -a base=()
    mapfile -t base < "$base_file"
    filter_empty base

    # Expected = base ∪ managed
    local expected_sorted
    expected_sorted=$(printf '%s\n' \
        "${base[@]+"${base[@]}"}" \
        "${managed[@]+"${managed[@]}"}" \
        | sort -u)

    # Diff
    local -a extra=() missing_managed=()
    mapfile -t extra < <(diff_lines "$installed_sorted" "$expected_sorted")
    filter_empty extra

    # Only flag missing from managed list (not base — base self-cleans silently)
    if [[ ${#managed[@]} -gt 0 ]]; then
        local managed_sorted
        managed_sorted=$(printf '%s\n' "${managed[@]}" | sort -u)
        mapfile -t missing_managed < <(diff_lines "$managed_sorted" "$installed_sorted")
        filter_empty missing_managed
    fi

    if [[ ${#missing_managed[@]} -eq 0 && ${#extra[@]} -eq 0 ]]; then
        echo "${label} match declared state."
        return 0
    fi

    [[ ${#missing_managed[@]} -gt 0 ]] && _handle_missing_managed "${missing_managed[@]}"
    [[ ${#extra[@]} -gt 0 ]] && _handle_extra_packages "$base_file" "${extra[@]}"
}

# --- Interactive prompts ---

# Prompt for extra packages (installed but in neither list).
# Usage: _handle_extra_packages <base_list_file> <package-names...>
_handle_extra_packages() {
    local base_file="$1"; shift
    local -a extras=("$@")

    echo ""
    echo "Untracked packages (installed but not declared or baseline):"
    printf "  - %s\n" "${extras[@]}"
    echo ""
    echo "  [b] Add to baseline (keep but don't manage)"
    echo "  [r] Remove them"
    echo "  [i] Ignore (will be asked again next time)"
    read -rp "Choice: " choice
    case "$choice" in
        [Bb])
            touch "$base_file"
            for pkg in "${extras[@]}"; do
                echo "$pkg" >> "$base_file"
            done
            echo "  Added ${#extras[@]} package(s) to baseline."
            ;;
        [Rr])
            _remove_extra_packages "${extras[@]}"
            ;;
        *)
            echo "  Ignored."
            ;;
    esac
}

# Prompt for missing managed packages (in .list but not installed).
# Cannot drop from .list — it's owned by build scripts.
# Usage: _handle_missing_managed <package-names...>
_handle_missing_managed() {
    local -a missing=("$@")

    echo ""
    echo "Missing managed packages (declared by build scripts but not installed):"
    printf "  + %s\n" "${missing[@]}"
    echo ""
    echo "  [i] Install them"
    echo "  [g] Ignore"
    read -rp "Choice: " choice
    case "$choice" in
        [Ii])
            _install_missing_packages "${missing[@]}"
            ;;
        *)
            echo "  Ignored."
            ;;
    esac
}
