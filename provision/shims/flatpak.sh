#!/usr/bin/env bash
## Flatpak build-time shim
##
## Shadows /usr/bin/flatpak as a bash function. Handles dual-mode operation:
##
##   flatpak remote-add  — container: curl .flatpakrepo to remotes.d;
##                          baremetal: execute real command
##   flatpak install     — container: write preinstall INI only;
##                          baremetal: install + write INI + record state
##   flatpak app-config  — write config to state dir for provisioning at boot
##
## Other subcommands pass through to /usr/bin/flatpak.

PREINSTALL_DIR="/etc/flatpak/preinstall.d"
FLATPAK_APPS_DIR="/usr/share/system-state.d/flatpak"
FLATPAK_REMOTES_LIST="/usr/share/system-state.d/packages/flatpak-remotes.list"

flatpak() {
    case "${1:-}" in
        remote-add) _flatpak_shim_remote_add "$@" ;;
        install)    _flatpak_shim_install "$@" ;;
        app-config) _flatpak_shim_app_config "$@" ;;
        *)          run_unprivileged /usr/bin/flatpak "$@" ;;
    esac
}

# flatpak remote-add --if-not-exists <name> <url>
# Container: download .flatpakrepo to /etc/flatpak/remotes.d/
# Baremetal: execute real command
# Both: record remote name (baremetal only for state file)
_flatpak_shim_remote_add() {
    shift # drop "remote-add"

    local name="" url=""
    local -a required=(--if-not-exists)
    local usage="flatpak remote-add ${required[*]} <name> <url>"

    for arg in "$@"; do
        case "$arg" in
            -*)
                local found=false
                for i in "${!required[@]}"; do
                    if [[ "${required[$i]}" == "$arg" ]]; then
                        unset 'required[$i]'
                        found=true
                        break
                    fi
                done
                if ! $found; then
                    echo "ERROR: flatpak shim: unexpected flag '$arg' for remote-add" >&2
                    echo "  Usage: $usage" >&2
                    return 1
                fi
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$arg"
                elif [[ -z "$url" ]]; then
                    url="$arg"
                else
                    echo "ERROR: flatpak shim: unexpected argument '$arg'" >&2
                    echo "  Usage: $usage" >&2
                    return 1
                fi
                ;;
        esac
    done

    # Re-index sparse array after unset
    required=("${required[@]}")
    if [[ ${#required[@]} -gt 0 ]]; then
        echo "ERROR: flatpak shim: missing required flags: ${required[*]}" >&2
        echo "  Usage: $usage" >&2
        return 1
    fi

    if [[ -z "$name" || -z "$url" ]]; then
        echo "ERROR: flatpak shim: usage: $usage" >&2
        return 1
    fi

    if [[ "$IS_CONTAINER" == true ]]; then
        # Container: download .flatpakrepo file directly (no D-Bus)
        local target="/etc/flatpak/remotes.d/${name}.flatpakrepo"
        if [[ -f "$target" ]]; then
            echo ":: Flatpak remote already exists: $name (skipped)"
            return 0
        fi
        mkdir -p /etc/flatpak/remotes.d
        curl --retry 3 -fsSLo "$target" "$url"
        echo ":: Downloaded flatpak remote: $name"
    else
        # Baremetal: run real command
        run_unprivileged /usr/bin/flatpak remote-add "$@" || return $?

        # Record remote for reconciliation (baremetal only)
        mkdir -p "$(dirname "$FLATPAK_REMOTES_LIST")"
        touch "$FLATPAK_REMOTES_LIST"
        if ! grep -qxF "$name" "$FLATPAK_REMOTES_LIST"; then
            echo "$name" >> "$FLATPAK_REMOTES_LIST"
        fi
    fi
}

# flatpak install --noninteractive [--system] <remote> <app-id>
# Both: write preinstall INI + store remote
# Container: return after writing (can't install without D-Bus)
# Baremetal: install + record state
_flatpak_shim_install() {
    shift # drop "install"

    local remote="" app_id=""
    local -a required=(--noninteractive)
    local -a optional=(--system)
    local usage="flatpak install ${required[*]} [${optional[*]}] <remote> <app-id>"

    for arg in "$@"; do
        case "$arg" in
            --system) ;; # optional, accepted but ignored (system is default)
            -*)
                local found=false
                for i in "${!required[@]}"; do
                    if [[ "${required[$i]}" == "$arg" ]]; then
                        unset 'required[$i]'
                        found=true
                        break
                    fi
                done
                if ! $found; then
                    echo "ERROR: flatpak shim: unexpected flag '$arg'" >&2
                    echo "  Usage: $usage" >&2
                    return 1
                fi
                ;;
            *)
                if [[ -z "$remote" ]]; then
                    remote="$arg"
                elif [[ -z "$app_id" ]]; then
                    app_id="$arg"
                else
                    echo "ERROR: flatpak shim: unexpected argument '$arg'" >&2
                    echo "  Usage: $usage" >&2
                    return 1
                fi
                ;;
        esac
    done

    # Re-index sparse array after unset
    required=("${required[@]}")
    if [[ ${#required[@]} -gt 0 ]]; then
        echo "ERROR: flatpak shim: missing required flags: ${required[*]}" >&2
        echo "  Usage: $usage" >&2
        return 1
    fi

    if [[ -z "$remote" || -z "$app_id" ]]; then
        echo "ERROR: flatpak shim: missing remote or app ID" >&2
        echo "  Usage: $usage" >&2
        return 1
    fi

    # Both modes: write preinstall INI + store remote
    mkdir -p "$PREINSTALL_DIR"
    cat > "${PREINSTALL_DIR}/${app_id}.ini" << EOF
[Flatpak Preinstall ${app_id}]
Install=true
EOF

    mkdir -p "${FLATPAK_APPS_DIR}/${app_id}"
    echo "$remote" > "${FLATPAK_APPS_DIR}/${app_id}/.remote"

    if [[ "$IS_CONTAINER" == true ]]; then
        echo ":: Registered flatpak app: ${app_id} (from ${remote})"
        return 0
    fi

    # Baremetal: actually install + record state
    run_unprivileged /usr/bin/flatpak install --noninteractive "$remote" "$app_id" || return $?
    pkg_shim_add flatpak "$app_id"
    echo ":: Installed flatpak app: ${app_id} (from ${remote})"
}

# flatpak app-config <app-id> <relative-path> <content>
# Writes config to state dir for provisioning at boot.
_flatpak_shim_app_config() {
    shift # drop "app-config"

    local app_id="${1:-}"
    local rel_path="${2:-}"
    local content="${3:-}"

    if [[ -z "$app_id" || -z "$rel_path" ]]; then
        echo "ERROR: flatpak shim: usage: flatpak app-config <app-id> <path> <content>" >&2
        return 1
    fi

    local target_dir
    target_dir="${FLATPAK_APPS_DIR}/${app_id}/$(dirname "$rel_path")"
    mkdir -p "$target_dir"
    printf '%s' "$content" > "${FLATPAK_APPS_DIR}/${app_id}/${rel_path}"

    echo ":: Provisioned config: ${app_id}/${rel_path}"
}
