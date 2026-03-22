#!/usr/bin/env bash
## Crudini build-time shim — copy-on-first-touch + mirror
##
## Shadows /usr/bin/crudini to track config file modifications.
## The real binary runs first; on success, the operation is mirrored
## on a state copy in /usr/share/system-state.d/files/<path>.
##
## On first mutating touch of a file, copies the original to the state
## directory (copy-on-first-touch). Subsequent operations are mirrored.
##
## In container builds, commands are executed but state is not recorded.
##
## Read-only operations (--get) pass through without recording.

FILES_STATE_DIR="/usr/share/system-state.d/files"

crudini_shim_reset() {
    [[ -f /run/.containerenv ]] && return 0
    rm -rf "$FILES_STATE_DIR"
    mkdir -p "$FILES_STATE_DIR"
}

# Extract the config_file path from crudini arguments.
# Skips the operation flag and any --option or --option=value flags.
# Returns the file path via stdout.
_crudini_shim_find_file() {
    local skip_next=false
    for arg in "$@"; do
        if $skip_next; then
            skip_next=false
            continue
        fi
        case "$arg" in
            --set|--get|--del|--merge) continue ;;
            --inplace|--list|--verbose) continue ;;
            --existing|--existing=*|--format=*|--ini-options=*|--list-sep=*|--output=*) continue ;;
            --*) continue ;;  # future-proof: skip unknown options
            *)   echo "$arg"; return 0 ;;
        esac
    done
    return 1
}

# Ensure the state copy exists (copy-on-first-touch).
_crudini_shim_ensure_copy() {
    local file="$1"
    local state_copy="${FILES_STATE_DIR}${file}"
    if [[ ! -f "$state_copy" ]]; then
        mkdir -p "$(dirname "$state_copy")"
        if [[ -f "$file" ]]; then
            cp "$file" "$state_copy"
        else
            touch "$state_copy"
        fi
    fi
}

crudini() {
    local op="${1:-}"

    case "$op" in
        --get)
            # Read-only — pass through, no recording
            /usr/bin/crudini "$@"
            ;;
        --set|--del|--merge)
            local file
            file=$(_crudini_shim_find_file "$@") || {
                /usr/bin/crudini "$@"
                return
            }

            # Run the real command first
            /usr/bin/crudini "$@" || return $?
            [[ -f /run/.containerenv ]] && return 0

            # On success, copy-on-first-touch + mirror to state
            _crudini_shim_ensure_copy "$file"

            local -a mirror_args=()
            local state_copy="${FILES_STATE_DIR}${file}"
            for arg in "$@"; do
                if [[ "$arg" == "$file" ]]; then
                    mirror_args+=("$state_copy")
                else
                    mirror_args+=("$arg")
                fi
            done
            /usr/bin/crudini "${mirror_args[@]}"
            ;;
        *)
            /usr/bin/crudini "$@"
            ;;
    esac
}
