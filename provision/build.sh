#!/usr/bin/env bash
## Main build orchestrator
set -oue pipefail
shopt -s nullglob

SCRIPT_DIR="$(dirname "$0")"
MODULE_DIR="${SCRIPT_DIR}/modules"

# Auto detect
source "${SCRIPT_DIR}/lib/detect.sh"

# Load module list from modules.conf (strips comments and blank lines)
mapfile -t modules < <(sed 's/#.*//; /^[[:space:]]*$/d' "${SCRIPT_DIR}/modules.conf")

# Resolve all modules first to fail early on missing scripts
resolved=()
for module in "${modules[@]}"; do
    if [[ "$module" == */ ]]; then
        for script in "${MODULE_DIR}/${module}"*.sh; do
            [[ -f "$script" ]] && resolved+=("$script")
        done
        continue
    fi

    if [[ -f "${MODULE_DIR}/${module}/${DISTRO}.sh" ]]; then
        resolved+=("${MODULE_DIR}/${module}/${DISTRO}.sh")
    elif [[ -f "${MODULE_DIR}/${module}.${DISTRO}.sh" ]]; then
        resolved+=("${MODULE_DIR}/${module}.${DISTRO}.sh")
    elif [[ -f "${MODULE_DIR}/${module}.sh" ]]; then
        resolved+=("${MODULE_DIR}/${module}.sh")
    else
        echo "ERROR: No script found for module '${module}'" >&2
        exit 1
    fi
done

# Shared helpers and shims used by modules
source "${SCRIPT_DIR}/lib/github.sh"
source "${SCRIPT_DIR}/lib/sudo.sh"
source "${SCRIPT_DIR}/shims/fs.sh"
source "${SCRIPT_DIR}/shims/flatpak.sh"
source "${SCRIPT_DIR}/shims/crudini.sh"
source "${SCRIPT_DIR}/shims/gearlever.sh"

# Package manager shim: records declared package state
source "${SCRIPT_DIR}/shims/package-manager.sh"
if [[ ! -f "${SCRIPT_DIR}/shims/${PACKAGE_MANAGER}.sh" ]]; then
    echo "ERROR: No shim found for package manager '${PACKAGE_MANAGER}'" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/shims/${PACKAGE_MANAGER}.sh"
fs_shim_reset
pkg_shim_reset

# /var is a tmpfs during bootc build - root's home must exist for gpg / package managers
[[ "$IS_CONTAINER" == true ]] && mkdir -p /var/roothome

# Execute resolved modules
for script in "${resolved[@]}"; do
    echo -e "\n===== Running module: ${script#"${MODULE_DIR}/"} ====="
    # shellcheck source=/dev/null
    source "${script}"
done

# Copy deploy scripts and service units to their destinations (container only)
if [[ "$IS_CONTAINER" == true ]]; then
    DEPLOY_SRC="${SCRIPT_DIR}/deploy"
    DEPLOY_DST="/usr/share/system-state.d/deploy"
    mkdir -p "$DEPLOY_DST"

    for file in "${DEPLOY_SRC}"/*.sh; do
        [[ -f "$file" ]] || continue
        cp "$file" "$DEPLOY_DST/"
        chmod +x "$DEPLOY_DST/${file##*/}"
    done

    mkdir -p /usr/lib/systemd/user
    for file in "${DEPLOY_SRC}"/*.service; do
        [[ -f "$file" ]] || continue
        cp "$file" /usr/lib/systemd/user/
        systemctl --global enable "${file##*/}"
    done
fi
