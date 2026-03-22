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

# Prompt for extra packages (installed but in neither list).
# Usage: handle_extra_packages <base_list_file> <package-names...>
handle_extra_packages() {
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
# Usage: handle_missing_managed <package-names...>
handle_missing_managed() {
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
