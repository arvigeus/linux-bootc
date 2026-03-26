#!/usr/bin/env bash
## File system state tracking shim — copy-on-first-touch + final state
##
## Shadows cp, mv, rm, touch, install, ln to track file modifications.
##
## State is recorded in /usr/share/system-state.d/files/:
##   expected/<path>  — the file as the build expects it to be (updated on every operation)
##   backup/<path>    — the file before any modification (saved once, on first touch)
##
## We use subdirectories rather than a .bak suffix to avoid collisions
## with real .bak files (vim, crudini --existing, backup tools) and to
## keep iteration simple — no filtering needed when walking the tree.
##
## For operations that can't be shimmed (shell redirects like > and >>),
## wrap them with touch:
##
##   touch /etc/foo.conf          # backup original, mark tracked
##   cat > /etc/foo.conf << 'EOF' # plain shell — no shim needed
##   content
##   EOF
##   touch /etc/foo.conf          # record final state
##
## In container builds, commands execute but state is not recorded.
## Bypass any shim with the full path: /usr/bin/cp, /usr/bin/mv, etc.

FILES_STATE_DIR="/usr/share/system-state.d/files"
_FS_BACKUP_DIR="${FILES_STATE_DIR}/backup"
_FS_EXPECTED_DIR="${FILES_STATE_DIR}/expected"
declare -gA _FS_TRACKED=()

# ── Internal helpers ───────────────────────────────────────────────



# Convert path to absolute (does not require existence).
_fs_resolve_path() {
    realpath -m -- "$1" 2>/dev/null || echo "$1"
}

# Returns 1 (skip) for temp / virtual filesystems.
_fs_should_track() {
    case "$1" in
        /tmp/*|/var/tmp/*|/proc/*|/sys/*|/dev/*) return 1 ;;
    esac
    return 0
}

# Create backup for the original file (once per path).
# For directories, backs up each file individually.
_fs_backup_original() {
    local file="$1"
    [[ -n "${_FS_TRACKED[$file]+x}" ]] && return 0
    [[ -e "$file" || -L "$file" ]] || return 0

    if [[ -d "$file" && ! -L "$file" ]]; then
        while IFS= read -r -d '' f; do
            _fs_backup_original "$f"
        done < <(/usr/bin/find "$file" \( -type f -o -type l \) -print0 2>/dev/null)
        return 0
    fi

    local orig="${_FS_BACKUP_DIR}${file}"
    [[ -e "$orig" ]] && return 0
    /usr/bin/mkdir -p "$(dirname "$orig")"
    /usr/bin/cp -a "$file" "$orig"
}

# Copy file to state dir (final state).
# For directories, records each file individually.
_fs_record_state() {
    local file="$1"
    if [[ -d "$file" && ! -L "$file" ]]; then
        while IFS= read -r -d '' f; do
            _fs_record_state "$f"
            _FS_TRACKED["$f"]=1
        done < <(/usr/bin/find "$file" \( -type f -o -type l \) -print0 2>/dev/null)
        return 0
    fi
    local state="${_FS_EXPECTED_DIR}${file}"
    /usr/bin/mkdir -p "$(dirname "$state")"
    /usr/bin/cp -a "$file" "$state"
}

# Remove final-state entry (keeps orig).
_fs_remove_state() {
    /usr/bin/rm -f "${_FS_EXPECTED_DIR}${1}"
}

# Convenience: backup original + mark tracked + record final state.
# Skips everything in containers or for non-tracked paths.
_fs_track_modify() {
    local file="$1"
    [[ "$IS_CONTAINER" == true ]] && return 0
    _fs_should_track "$file" || return 0
    _fs_backup_original "$file"
    _FS_TRACKED["$file"]=1
    _fs_record_state "$file"
}

# Convenience: backup original + mark tracked + remove final state.
_fs_track_delete() {
    local file="$1"
    [[ "$IS_CONTAINER" == true ]] && return 0
    _fs_should_track "$file" || return 0
    _fs_backup_original "$file"
    _FS_TRACKED["$file"]=1
    _fs_remove_state "$file"
}

# Remove from tracked set + remove final-state entry.
_fs_untrack() {
    local file="$1"
    unset '_FS_TRACKED['"$file"']'
    _fs_remove_state "$file"
}

# ── Argument parser ────────────────────────────────────────────────
#
# Separates flags from positional arguments.  Per-command tables list
# which short / long flags consume a value argument.
#
# Outputs (global arrays, reused across calls):
#   _fs_flags=()         all flag tokens (preserved for pass-through)
#   _fs_positionals=()   non-flag arguments in order
#   _fs_target_dir=""    value of -t / --target-directory (if any)
#   _fs_has_d_flag       true when -d is present  (install -d)
#   _fs_has_r_flag       true when -r/-R/-a/--recursive present
#   _fs_has_T_flag       true when -T/--no-target-directory present

_fs_parse_args() {
    local cmd="$1"; shift

    _fs_flags=()
    _fs_positionals=()
    _fs_target_dir=""
    _fs_has_d_flag=false
    _fs_has_r_flag=false
    _fs_has_T_flag=false

    # Per-command value-taking flags
    local vshort vlong
    case "$cmd" in
        cp)      vshort="tS";     vlong="target-directory|suffix|backup|sparse|reflink" ;;
        mv)      vshort="tS";     vlong="target-directory|suffix|backup" ;;
        rm)      vshort="";       vlong="" ;;
        install) vshort="tmogSZ"; vlong="target-directory|mode|owner|group|suffix|backup|context" ;;
        ln)      vshort="tS";     vlong="target-directory|suffix|backup" ;;
        touch)   vshort="rdt";    vlong="reference|date" ;;
    esac

    local end_of_flags=false
    local skip_next=false
    local capture_target_dir=false

    for arg in "$@"; do
        # Value for a previous flag
        if $skip_next; then
            _fs_flags+=("$arg")
            $capture_target_dir && { _fs_target_dir="$arg"; capture_target_dir=false; }
            skip_next=false
            continue
        fi

        if $end_of_flags; then
            _fs_positionals+=("$arg")
            continue
        fi

        case "$arg" in
            --)
                end_of_flags=true
                ;;
            --*=*)
                local flag_name="${arg%%=*}"; flag_name="${flag_name#--}"
                _fs_flags+=("$arg")
                [[ "$flag_name" == "target-directory" ]] && _fs_target_dir="${arg#*=}"
                case "$flag_name" in
                    recursive)            _fs_has_r_flag=true ;;
                    no-target-directory)  _fs_has_T_flag=true ;;
                esac
                ;;
            --*)
                local flag_name="${arg#--}"
                _fs_flags+=("$arg")
                case "$flag_name" in
                    recursive)            _fs_has_r_flag=true ;;
                    no-target-directory)  _fs_has_T_flag=true ;;
                esac
                if [[ -n "$vlong" ]] && [[ "|${vlong}|" == *"|${flag_name}|"* ]]; then
                    skip_next=true
                    [[ "$flag_name" == "target-directory" ]] && capture_target_dir=true
                fi
                ;;
            -?*)
                # Combined short flags  e.g. -Dm644
                _fs_flags+=("$arg")
                local chars="${arg#-}"
                local i=0
                while [[ $i -lt ${#chars} ]]; do
                    local c="${chars:$i:1}"
                    case "$c" in
                        r|R|a) _fs_has_r_flag=true ;;
                        T)     _fs_has_T_flag=true ;;
                        d)     _fs_has_d_flag=true ;;
                    esac
                    if [[ -n "$vshort" && "$vshort" == *"$c"* ]]; then
                        local rest="${chars:$((i+1))}"
                        if [[ -n "$rest" ]]; then
                            [[ "$c" == "t" ]] && _fs_target_dir="$rest"
                        else
                            skip_next=true
                            [[ "$c" == "t" ]] && capture_target_dir=true
                        fi
                        break
                    fi
                    (( i++ )) || true
                done
                ;;
            *)
                _fs_positionals+=("$arg")
                ;;
        esac
    done
}

# ── Destination resolution ─────────────────────────────────────────
#
# Populates _fs_destinations=() and (for mv) _fs_mv_sources=().

_fs_resolve_destinations() {
    local cmd="$1"
    _fs_destinations=()
    _fs_mv_sources=()

    case "$cmd" in
        rm|touch)
            local p
            for p in "${_fs_positionals[@]}"; do
                _fs_destinations+=("$(_fs_resolve_path "$p")")
            done
            return
            ;;
        install)
            $_fs_has_d_flag && return 0   # install -d: dirs only
            ;;&                            # fall through
        cp|mv|ln|install)
            local n=${#_fs_positionals[@]}
            [[ $n -eq 0 ]] && return 0

            if [[ -n "$_fs_target_dir" ]]; then
                # -t DIR: all positionals are sources
                local dir
                dir=$(_fs_resolve_path "$_fs_target_dir")
                local p
                for p in "${_fs_positionals[@]}"; do
                    [[ "$cmd" == "mv" ]] && _fs_mv_sources+=("$(_fs_resolve_path "$p")")
                    _fs_destinations+=("${dir}/$(/usr/bin/basename "$p")")
                done
            elif [[ $n -eq 1 && "$cmd" == "ln" ]]; then
                # ln -s target  (link created in cwd with same basename)
                _fs_destinations+=("$(_fs_resolve_path "./$(/usr/bin/basename "${_fs_positionals[0]}")")")
            elif [[ $n -ge 2 ]]; then
                local last
                last=$(_fs_resolve_path "${_fs_positionals[$((n-1))]}")

                if $_fs_has_T_flag || { [[ $n -eq 2 ]] && [[ ! -d "$last" ]]; }; then
                    # Last positional is the literal destination
                    local i
                    for (( i=0; i<n-1; i++ )); do
                        [[ "$cmd" == "mv" ]] && _fs_mv_sources+=("$(_fs_resolve_path "${_fs_positionals[$i]}")")
                    done
                    _fs_destinations+=("$last")
                else
                    # Last positional is a directory — multi-source-to-dir
                    local i
                    for (( i=0; i<n-1; i++ )); do
                        local src="${_fs_positionals[$i]}"
                        [[ "$cmd" == "mv" ]] && _fs_mv_sources+=("$(_fs_resolve_path "$src")")
                        _fs_destinations+=("${last}/$(/usr/bin/basename "$src")")
                    done
                fi
            fi
            ;;
    esac
}

# ── Reset ──────────────────────────────────────────────────────────

fs_shim_reset() {
    [[ "$IS_CONTAINER" == true ]] && return 0
    _FS_TRACKED=()
    /usr/bin/rm -rf "$FILES_STATE_DIR"
    /usr/bin/mkdir -p "$_FS_BACKUP_DIR" "$_FS_EXPECTED_DIR"
}

# ── Shimmed commands ───────────────────────────────────────────────

cp() {
    if [[ "$IS_CONTAINER" == true ]]; then /usr/bin/cp "$@"; return $?; fi

    _fs_parse_args cp "$@"
    _fs_resolve_destinations cp

    # Backup existing destinations before overwrite
    local dest
    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _fs_backup_original "$dest"
    done

    /usr/bin/cp "$@" || return $?

    # Record final state
    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _FS_TRACKED["$dest"]=1
        _fs_record_state "$dest"
    done
}

mv() {
    if [[ "$IS_CONTAINER" == true ]]; then /usr/bin/mv "$@"; return $?; fi

    _fs_parse_args mv "$@"
    _fs_resolve_destinations mv

    # Backup sources (will be gone after move) and existing destinations
    local src dest
    for src in "${_fs_mv_sources[@]}"; do
        _fs_should_track "$src" || continue
        _fs_backup_original "$src"
    done
    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _fs_backup_original "$dest"
    done

    /usr/bin/mv "$@" || return $?

    # Untrack moved-away sources
    for src in "${_fs_mv_sources[@]}"; do
        _fs_should_track "$src" || continue
        [[ -n "${_FS_TRACKED[$src]+x}" ]] && _fs_untrack "$src"
    done

    # Record destinations
    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _FS_TRACKED["$dest"]=1
        _fs_record_state "$dest"
    done
}

rm() {
    if [[ "$IS_CONTAINER" == true ]]; then /usr/bin/rm "$@"; return $?; fi

    _fs_parse_args rm "$@"
    _fs_resolve_destinations rm

    # Backup BEFORE deletion — files will be gone afterwards
    local -a all_tracked=()
    local target
    for target in "${_fs_destinations[@]}"; do
        _fs_should_track "$target" || continue
        if [[ -d "$target" && ! -L "$target" ]]; then
            while IFS= read -r -d '' f; do
                _fs_backup_original "$f"
                all_tracked+=("$f")
            done < <(/usr/bin/find "$target" \( -type f -o -type l \) -print0 2>/dev/null)
        elif [[ -e "$target" || -L "$target" ]]; then
            _fs_backup_original "$target"
            all_tracked+=("$target")
        fi
    done

    /usr/bin/rm "$@"
    local rc=$?

    local f
    for f in "${all_tracked[@]}"; do
        _FS_TRACKED["$f"]=1
        _fs_remove_state "$f"
    done

    return "$rc"
}

touch() {
    if [[ "$IS_CONTAINER" == true ]]; then /usr/bin/touch "$@"; return $?; fi

    _fs_parse_args touch "$@"
    _fs_resolve_destinations touch

    # Backup before touch (files may already exist)
    local dest
    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _fs_backup_original "$dest"
    done

    /usr/bin/touch "$@" || return $?

    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _FS_TRACKED["$dest"]=1
        _fs_record_state "$dest"
    done
}

install() {
    if [[ "$IS_CONTAINER" == true ]]; then /usr/bin/install "$@"; return $?; fi

    _fs_parse_args install "$@"

    # install -d: directory creation only — no file tracking
    if $_fs_has_d_flag; then
        /usr/bin/install "$@"
        return $?
    fi

    _fs_resolve_destinations install

    local dest
    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _fs_backup_original "$dest"
    done

    /usr/bin/install "$@" || return $?

    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _FS_TRACKED["$dest"]=1
        _fs_record_state "$dest"
    done
}

ln() {
    if [[ "$IS_CONTAINER" == true ]]; then /usr/bin/ln "$@"; return $?; fi

    _fs_parse_args ln "$@"
    _fs_resolve_destinations ln

    local dest
    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _fs_backup_original "$dest"
    done

    /usr/bin/ln "$@" || return $?

    for dest in "${_fs_destinations[@]}"; do
        _fs_should_track "$dest" || continue
        _FS_TRACKED["$dest"]=1
        _fs_record_state "$dest"
    done
}
