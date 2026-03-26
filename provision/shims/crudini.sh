#!/usr/bin/env bash
## Crudini build-time shim — delegates file tracking to fs.sh
##
## Shadows /usr/bin/crudini to track config file modifications.
## The real binary runs first; on success, the final file state is
## recorded via fs.sh helpers (backup original + copy final state).
##
## In container builds, commands are executed but state is not recorded.
##
## Read-only operations (--get) pass through without recording.
##
## Requires: fs.sh must be sourced before this file.

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
            [[ "$IS_CONTAINER" == true ]] && return 0

            # Record via fs.sh: backup original on first touch, copy final state
            _fs_backup_original "$file"
            _FS_TRACKED["$file"]=1
            local state="${_FS_EXPECTED_DIR}${file}"
            /usr/bin/mkdir -p "$(dirname "$state")"
            /usr/bin/cp -a "$file" "$state"
            ;;
        *)
            /usr/bin/crudini "$@"
            ;;
    esac
}
