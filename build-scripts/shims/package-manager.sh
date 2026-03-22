#!/usr/bin/env bash
## Package manager build-time shim — shared helpers
##
## Provides functions used by per-manager shims (dnf.sh, pacman.sh, paru.sh)
## to record declared package state. Per-manager shims skip state recording
## in container builds after executing the real command.
##
## Generated files (bootstrap only):
##
##   /usr/share/system-state.d/packages/<manager>.list      — managed packages (one per line)
##   /usr/share/system-state.d/packages/<manager>.base.list — unmanaged baseline packages
##   /usr/share/system-state.d/packages/repos.list          — repo operations (type\targs)

PKG_STATE_DIR="/usr/share/system-state.d/packages"

# Called once at build start. Wipes managed lists (.list) and repos for a
# clean rebuild, but preserves .base.list files.
pkg_shim_reset() {
    [[ -f /run/.containerenv ]] && return 0
    mkdir -p "$PKG_STATE_DIR"
    # Remove managed lists and repos, but keep *.base.list
    for f in "$PKG_STATE_DIR"/*.list; do
        [[ "$f" == *.base.list ]] && continue
        rm -f "$f"
    done
    rm -f "$PKG_STATE_DIR"/repos.list
}

# pkg_shim_add <manager> <packages...>
# Appends packages to <manager>.list (managed).
pkg_shim_add() {
    local manager="$1"; shift
    local list="${PKG_STATE_DIR}/${manager}.list"
    touch "$list"
    for pkg in "$@"; do
        echo "$pkg" >> "$list"
    done
}

# pkg_shim_remove <manager> <packages...>
# Removes matching lines from <manager>.list and <manager>.base.list.
pkg_shim_remove() {
    local manager="$1"; shift
    local list="${PKG_STATE_DIR}/${manager}.list"
    local base="${PKG_STATE_DIR}/${manager}.base.list"
    for pkg in "$@"; do
        if [[ -f "$list" ]]; then
            grep -vxF "$pkg" "$list" > "${list}.tmp" || true
            mv "${list}.tmp" "$list"
        fi
        if [[ -f "$base" ]]; then
            grep -vxF "$pkg" "$base" > "${base}.tmp" || true
            mv "${base}.tmp" "$base"
        fi
    done
}

# pkg_shim_require_flags "$*" <required-flags...>
# Validates that all required flags are present in the argument string.
# Note: pass "$*" (single string), not "$@".
pkg_shim_require_flags() {
    local args="$1"; shift
    local missing=()
    for flag in "$@"; do
        if ! echo " $args " | grep -q " ${flag} "; then
            missing+=("$flag")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: package shim: missing required flags: ${missing[*]}" >&2
        echo "  In command: $args" >&2
        return 1
    fi
    return 0
}

# pkg_shim_add_repo <type> <args...>
# Records a repo operation to repos.list. Format: type<TAB>args.
pkg_shim_add_repo() {
    local type="$1"; shift
    local list="${PKG_STATE_DIR}/repos.list"
    touch "$list"
    echo "${type}	$*" >> "$list"
}
