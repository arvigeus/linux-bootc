#!/usr/bin/env bash
## Detect DISTRO, PACKAGE_MANAGER, and IS_CONTAINER from the running system

# shellcheck disable=SC2034 # sourced by other scripts

# Container detection — true if running inside a container (podman/docker)
IS_CONTAINER=false
[[ -f /run/.containerenv ]] && IS_CONTAINER=true

# User home — needed so modules can write user-level config (dotfiles, XDG dirs)
# Container: /etc/skel (skeleton copied to real home on first boot / by deploy script)
# Baremetal: read from the non-root user's login environment to respect custom paths
if [[ "$IS_CONTAINER" == true ]]; then
    HOME=/etc/skel
else
    _target_user=""
    if [[ -n "${SUDO_USER:-}" ]]; then
        _target_user="$SUDO_USER"
    else
        # Fallback: first user with UID >= 1000
        _target_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }')
    fi

    if [[ -n "$_target_user" ]]; then
        # Read the user's actual environment (respects custom paths set in their shell profile)
        HOME=$(getent passwd "$_target_user" | cut -d: -f6)
        # shellcheck disable=SC2016 # single quotes intentional — expanded by the user's login shell, not this one
        if _user_env=$(su - "$_target_user" -c '
            echo "${XDG_CONFIG_HOME:-}"
            echo "${XDG_DATA_HOME:-}"
            echo "${XDG_STATE_HOME:-}"
            echo "${XDG_CACHE_HOME:-}"
        ' 2>/dev/null); then
            mapfile -t _xdg_vals <<< "$_user_env"
            [[ -n "${_xdg_vals[0]:-}" ]] && XDG_CONFIG_HOME="${_xdg_vals[0]}"
            [[ -n "${_xdg_vals[1]:-}" ]] && XDG_DATA_HOME="${_xdg_vals[1]}"
            [[ -n "${_xdg_vals[2]:-}" ]] && XDG_STATE_HOME="${_xdg_vals[2]}"
            [[ -n "${_xdg_vals[3]:-}" ]] && XDG_CACHE_HOME="${_xdg_vals[3]}"
        fi
    fi
fi
export HOME

# Fall back to XDG defaults for anything not set by the user's environment
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME

mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

DISTRO=$(. /etc/os-release && echo "$ID")
if [[ -z "$DISTRO" ]]; then
    echo "ERROR: Could not detect DISTRO" >&2
    exit 1
fi

if command -v dnf &>/dev/null; then
    PACKAGE_MANAGER=dnf
elif command -v pacman &>/dev/null; then
    PACKAGE_MANAGER=pacman
else
    echo "ERROR: Could not detect package manager" >&2
    exit 1
fi
