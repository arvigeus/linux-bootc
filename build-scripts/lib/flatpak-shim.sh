#!/usr/bin/env bash
## Flatpak build-time shim
##
## Flatpak apps can't be installed inside a container image build — they need
## a running system with D-Bus, user sessions, etc. This shim overrides the
## `flatpak` command as a bash function so modules can write natural-looking
## install commands that actually generate declarative files for later:
##
##   flatpak install --noninteractive --user <remote> <app>
##   flatpak app-config <app> config/settings.json '{"key": "val"}'
##
## The `install` command doesn't install anything — it writes an INI file that
## a post-deploy script reads at first boot to do the real installation.
##
## Generated files:
##
##   /etc/flatpak/preinstall.d/<app-id>.ini   — INI file matching the Flatpak 1.17+
##                                               native preinstall format (there is no
##                                               CLI to generate these, so the shim is
##                                               needed even after upstream ships support;
##                                               only the post-deploy installer goes away)
##   /usr/share/flatpak-apps.d/<app-id>/      — config files to provision into
##                                               ~/.var/app/<app-id>/ at runtime
##   /usr/share/flatpak-apps.d/<app-id>/.remote — tracks which remote to use (our
##                                               extension; native format has no remote)
##
## All other flatpak subcommands (e.g., remote-add) pass through to /usr/bin/flatpak.

PREINSTALL_DIR="/etc/flatpak/preinstall.d"
FLATPAK_APPS_DIR="/usr/share/flatpak-apps.d"

flatpak() {
    case "${1:-}" in
        install)
            _flatpak_shim_install "$@"
            ;;
        app-config)
            _flatpak_shim_app_config "$@"
            ;;
        *)
            /usr/bin/flatpak "$@"
            ;;
    esac
}

# flatpak install --noninteractive --user <remote> <app-id>
# Generates a preinstall.d INI file and records the remote.
# Strict: both --noninteractive and --user are required. Anything else errors.
_flatpak_shim_install() {
    shift # drop "install"

    local remote="" app_id=""
    local -a required=(--noninteractive --user)
    local usage="flatpak install ${required[*]} <remote> <app-id>"

    for arg in "$@"; do
        case "$arg" in
            -*)
                # Check if this flag is in the required list
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
                    echo "ERROR: flatpak: unexpected argument '$arg'" >&2
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
        echo "ERROR: flatpak: missing remote or app ID" >&2
        echo "  Usage: $usage" >&2
        return 1
    fi

    mkdir -p "$PREINSTALL_DIR"
    cat > "${PREINSTALL_DIR}/${app_id}.ini" << EOF
[Flatpak Preinstall ${app_id}]
Install=true
EOF

    # Store remote so the post-deploy script knows where to install from.
    # The native preinstall format has no remote field — this is our extension.
    mkdir -p "${FLATPAK_APPS_DIR}/${app_id}"
    echo "$remote" > "${FLATPAK_APPS_DIR}/${app_id}/.remote"

    echo ":: Registered flatpak app: ${app_id} (from ${remote})"
}

# flatpak app-config <app-id> <relative-path> <content>
# Writes config content that gets copied to ~/.var/app/<app-id>/<relative-path>
# at first boot by the post-deploy script.
_flatpak_shim_app_config() {
    shift # drop "app-config"

    local app_id="${1:-}"
    local rel_path="${2:-}"
    local content="${3:-}"

    if [[ -z "$app_id" || -z "$rel_path" ]]; then
        echo "ERROR: flatpak: usage: flatpak app-config <app-id> <path> <content>" >&2
        return 1
    fi

    local target_dir
    target_dir="${FLATPAK_APPS_DIR}/${app_id}/$(dirname "$rel_path")"
    mkdir -p "$target_dir"
    printf '%s' "$content" > "${FLATPAK_APPS_DIR}/${app_id}/${rel_path}"

    echo ":: Provisioned config: ${app_id}/${rel_path}"
}
