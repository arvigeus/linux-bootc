#!/usr/bin/env bash
## Paru build-time shim
##
## Shadows /usr/bin/paru as a bash function. The real binary runs first;
## on success, the operation is recorded for later reconciliation.
##
## In container builds, commands are validated and executed but state
## is not recorded.
##
## The operation flag (-S, -R, etc.) MUST be the first argument.
## Removal enforces -Rns for clean removal (no orphans, no .pacsave files).

_paru_shim_exec() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" /usr/bin/paru "$@"
    else
        /usr/bin/paru "$@"
    fi
}

paru() {
    case "${1:-}" in
        -S*) _paru_shim_sync "$@" ;;
        -R*) _paru_shim_remove "$@" ;;
        -*)  _paru_shim_exec "$@" ;;
        *)
            echo "ERROR: paru shim: operation flag (-S, -R, etc.) must be the first argument" >&2
            echo "  Got: paru $*" >&2
            return 1
            ;;
    esac
}

# -S* handler: install packages or system upgrade
_paru_shim_sync() {
    local op_arg="$1"

    # Collect packages (non-flag positional args, skip the operation flag)
    local -a pkgs=()
    for arg in "${@:2}"; do
        case "$arg" in
            -*) ;;
            *)  pkgs+=("$arg") ;;
        esac
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        # No packages — check if this is -Syu (upgrade) or bare -Sy (unsafe)
        if [[ "$op_arg" == *u* ]]; then
            _paru_shim_exec "$@"
            return
        fi
        if [[ "$op_arg" == *y* ]]; then
            echo "ERROR: paru shim: bare -Sy is unsafe; use -Syu to upgrade" >&2
            return 1
        fi
        # Other -S with no packages (e.g. -Ss search) — pass through
        _paru_shim_exec "$@"
        return
    fi

    # Has packages — require --noconfirm and --needed
    pkg_shim_require_flags "$*" --noconfirm --needed || return 1

    # Strip repo prefix (aur/pkg -> pkg) and record
    local -a stripped=()
    for pkg in "${pkgs[@]}"; do
        stripped+=("${pkg##*/}")
    done

    _paru_shim_exec "$@" || return $?
    [[ -f /run/.containerenv ]] && return 0
    pkg_shim_add paru "${stripped[@]}"
}

# -R* handler: remove packages
_paru_shim_remove() {
    local op="$1"
    if [[ "$op" != *n* || "$op" != *s* ]]; then
        echo "ERROR: paru shim: use -Rns for clean removal (got: $op)" >&2
        return 1
    fi

    local -a pkgs=()
    for arg in "${@:2}"; do
        case "$arg" in
            -*) ;;
            *)  pkgs+=("$arg") ;;
        esac
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        _paru_shim_exec "$@"
        return
    fi

    pkg_shim_require_flags "$*" --noconfirm || return 1

    _paru_shim_exec "$@" || return $?
    [[ -f /run/.containerenv ]] && return 0
    pkg_shim_remove paru "${pkgs[@]}"
}
