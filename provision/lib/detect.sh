#!/usr/bin/env bash
## Detect DISTRO, PACKAGE_MANAGER, and IS_CONTAINER from the running system

# shellcheck disable=SC2034 # sourced by other scripts

# Container detection — true if running inside a container (podman/docker)
IS_CONTAINER=false
[[ -f /run/.containerenv ]] && IS_CONTAINER=true

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
