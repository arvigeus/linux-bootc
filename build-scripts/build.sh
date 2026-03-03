#!/usr/bin/env bash
## Main build orchestrator - sources modules in order
set -oue pipefail
shopt -s nullglob

MODULE_DIR="$(dirname "$0")/modules"

if [[ -z "${DISTRO:-}" ]]; then
    echo "ERROR: DISTRO is not set" >&2
    exit 1
fi

if [[ -z "${PACKAGE_MANAGER:-}" ]]; then
    echo "ERROR: PACKAGE_MANAGER is not set" >&2
    exit 1
fi

# /var is a tmpfs during bootc build - root's home must exist for gpg / package managers
[[ -f /run/.containerenv ]] && mkdir -p /var/roothome

# Module resolution order for "<path>":
#   1. modules/<path>/${DISTRO}.sh        (per-distro directory)
#   2. modules/<path>.${DISTRO}.sh        (per-distro suffix)
#   3. modules/<path>.sh                  (shared)
# Use "<path>/" to source all scripts in a directory.
modules=(
    base/config-parsers
    base/post-deploy
    base/repos
    base/flatpak
    base/appimage
	dev/editors/
    multimedia/codecs
    multimedia/video/
)

for module in "${modules[@]}"; do
    # Glob: source all .sh files in directory
    if [[ "$module" == */ ]]; then
        for script in "${MODULE_DIR}/${module}"*.sh; do
            [[ -f "$script" ]] || continue
            echo ":: Running module: ${script#"${MODULE_DIR}/"}"
            # shellcheck source=/dev/null
            source "${script}"
        done
        continue
    fi

    # Single module resolution
    if [[ -f "${MODULE_DIR}/${module}/${DISTRO}.sh" ]]; then
        script="${MODULE_DIR}/${module}/${DISTRO}.sh"
    elif [[ -f "${MODULE_DIR}/${module}.${DISTRO}.sh" ]]; then
        script="${MODULE_DIR}/${module}.${DISTRO}.sh"
    elif [[ -f "${MODULE_DIR}/${module}.sh" ]]; then
        script="${MODULE_DIR}/${module}.sh"
    else
        echo "ERROR: No script found for module '${module}'" >&2
        exit 1
    fi

    echo ":: Running module: ${script#"${MODULE_DIR}/"}"
    # shellcheck source=/dev/null
    source "${script}"
done
