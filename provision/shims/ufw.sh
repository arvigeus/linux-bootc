#!/usr/bin/env bash
## UFW build-time shim
##
## Shadows /usr/sbin/ufw so modules can write natural-looking ufw commands.
## Behavior differs intentionally between modes:
##
##   Bootstrap (IS_CONTAINER != true):
##     Commands execute immediately against the live system.
##     Config files are tracked with a touch sandwich (fs.sh handles
##     backup/record automatically):
##       touch <files>       # backup originals
##       /usr/sbin/ufw ...   # run command
##       touch <files>       # record final state
##     Drift detection and reconciliation are handled by files.sh.
##
##   Container (IS_CONTAINER == true):
##     Commands cannot execute (no kernel). Declared state is recorded to
##     structured files for post-deploy replay on first boot:
##       rules.list, defaults.list, config.list
##
## Command dispatch:
##
##   allow / deny / reject / insert / route / delete
##     Bootstrap: touch sandwich around real ufw
##     Container: record to rules.list (delete removes from rules.list)
##
##   default
##     Bootstrap: touch sandwich around real ufw
##     Container: record to defaults.list (last-wins per direction)
##
##   enable / disable / logging
##     Bootstrap: touch sandwich around real ufw
##     Container: record to config.list (last-wins)
##
##   reset
##     Bootstrap: touch sandwich around ufw reset --force
##     Container: clear all structured state files
##
##   status
##     Bootstrap: pass through to real ufw
##     Container: emulate from structured state files
##
##   reload
##     Bootstrap: pass through to real ufw
##     Container: no-op
##
##   Everything else (version, --help, app, ...)
##     Pass through to /usr/sbin/ufw
##
## Numeric deletes (ufw delete NUM) are rejected in all modes — non-declarative.
##
## Bypass the shim with the full path: /usr/sbin/ufw

UFW_STATE_DIR="/usr/share/system-state.d/ufw"
_UFW_RULES_LIST="${UFW_STATE_DIR}/rules.list"
_UFW_DEFAULTS_LIST="${UFW_STATE_DIR}/defaults.list"
_UFW_CONFIG_LIST="${UFW_STATE_DIR}/config.list"

# Config files tracked in bootstrap mode (overridable in tests)
_UFW_CONFIG_FILES=(
    /etc/ufw/user.rules
    /etc/ufw/user6.rules
    /etc/ufw/ufw.conf
)

# ── Container helpers ──────────────────────────────────────────────

_ufw_ensure_state_dir() {
    /usr/bin/mkdir -p "$UFW_STATE_DIR"
}

_ufw_record_rule() {
    _ufw_ensure_state_dir
    echo "$*" >> "$_UFW_RULES_LIST"
}

_ufw_remove_rule() {
    [[ -f "$_UFW_RULES_LIST" ]] || return 0
    local rule="$*"
    if grep -qxF -- "$rule" "$_UFW_RULES_LIST" 2>/dev/null; then
        grep -vxF -- "$rule" "$_UFW_RULES_LIST" > "${_UFW_RULES_LIST}.tmp" || true
        /usr/bin/mv "${_UFW_RULES_LIST}.tmp" "$_UFW_RULES_LIST"
    fi
}

# ── Shimmed command ───────────────────────────────────────────────

ufw() {
    case "${1:-}" in
        allow|deny|reject)   _ufw_shim_rule "$@" ;;
        insert)              _ufw_shim_insert "$@" ;;
        route)               _ufw_shim_route "$@" ;;
        delete)              _ufw_shim_delete "$@" ;;
        default)             _ufw_shim_default "$@" ;;
        enable|disable)      _ufw_shim_state "$@" ;;
        logging)             _ufw_shim_logging "$@" ;;
        reset)               _ufw_shim_reset_cmd ;;
        status)              _ufw_shim_status "$@" ;;
        reload)              _ufw_shim_reload ;;
        *)                   /usr/sbin/ufw "$@" ;;
    esac
}

# ── allow / deny / reject ─────────────────────────────────────────

_ufw_shim_rule() {
    if [[ "$IS_CONTAINER" != true ]]; then
        touch "${_UFW_CONFIG_FILES[@]}"
        /usr/sbin/ufw "$@" || return $?
        touch "${_UFW_CONFIG_FILES[@]}"
    else
        _ufw_record_rule "$@"
    fi
}

# ── insert ────────────────────────────────────────────────────────

_ufw_shim_insert() {
    if [[ "$IS_CONTAINER" != true ]]; then
        touch "${_UFW_CONFIG_FILES[@]}"
        /usr/sbin/ufw "$@" || return $?
        touch "${_UFW_CONFIG_FILES[@]}"
    else
        # Record rule without "insert N" prefix: $1=insert, $2=N, $3+=rule
        local -a rule_args=("${@:3}")
        _ufw_record_rule "${rule_args[@]}"
    fi
}

# ── route ─────────────────────────────────────────────────────────

_ufw_shim_route() {
    if [[ "$IS_CONTAINER" != true ]]; then
        touch "${_UFW_CONFIG_FILES[@]}"
        /usr/sbin/ufw "$@" || return $?
        touch "${_UFW_CONFIG_FILES[@]}"
    else
        _ufw_record_rule "$@"
    fi
}

# ── delete ────────────────────────────────────────────────────────

_ufw_shim_delete() {
    local after_delete="${2:-}"

    # Reject positional deletes — non-declarative
    if [[ "$after_delete" =~ ^[0-9]+$ ]]; then
        echo "ERROR: ufw shim: 'delete NUM' is not allowed in build scripts." >&2
        echo "  Use 'ufw delete <rule>' instead (e.g., 'ufw delete allow 22/tcp')." >&2
        return 1
    fi

    if [[ "$IS_CONTAINER" != true ]]; then
        touch "${_UFW_CONFIG_FILES[@]}"
        /usr/sbin/ufw "$@" || return $?
        touch "${_UFW_CONFIG_FILES[@]}"
    else
        local -a rule_args=("${@:2}")
        _ufw_remove_rule "${rule_args[*]}"
    fi
}

# ── default ───────────────────────────────────────────────────────

_ufw_shim_default() {
    local action="${2:-}"
    local direction="${3:-}"

    if [[ -z "$action" || -z "$direction" ]]; then
        echo "ERROR: ufw shim: usage: ufw default <allow|deny|reject> <incoming|outgoing|routed>" >&2
        return 1
    fi

    if [[ "$IS_CONTAINER" != true ]]; then
        touch "${_UFW_CONFIG_FILES[@]}"
        /usr/sbin/ufw "$@" || return $?
        touch "${_UFW_CONFIG_FILES[@]}"
    else
        _ufw_ensure_state_dir
        /usr/bin/touch "$_UFW_DEFAULTS_LIST"
        if grep -q " ${direction}$" "$_UFW_DEFAULTS_LIST" 2>/dev/null; then
            grep -v " ${direction}$" "$_UFW_DEFAULTS_LIST" > "${_UFW_DEFAULTS_LIST}.tmp" || true
            /usr/bin/mv "${_UFW_DEFAULTS_LIST}.tmp" "$_UFW_DEFAULTS_LIST"
        fi
        echo "${action} ${direction}" >> "$_UFW_DEFAULTS_LIST"
    fi
}

# ── enable / disable ──────────────────────────────────────────────

_ufw_shim_state() {
    local cmd="$1"

    if [[ "$IS_CONTAINER" != true ]]; then
        touch "${_UFW_CONFIG_FILES[@]}"
        /usr/sbin/ufw "$@" || return $?
        touch "${_UFW_CONFIG_FILES[@]}"
    else
        _ufw_ensure_state_dir
        /usr/bin/touch "$_UFW_CONFIG_LIST"
        grep -vE "^(enabled|disabled)$" "$_UFW_CONFIG_LIST" > "${_UFW_CONFIG_LIST}.tmp" 2>/dev/null || true
        /usr/bin/mv "${_UFW_CONFIG_LIST}.tmp" "$_UFW_CONFIG_LIST"
        echo "${cmd}d" >> "$_UFW_CONFIG_LIST"
    fi
}

# ── logging ───────────────────────────────────────────────────────

_ufw_shim_logging() {
    local level="${2:-}"

    if [[ -z "$level" ]]; then
        echo "ERROR: ufw shim: usage: ufw logging <on|off|low|medium|high|full>" >&2
        return 1
    fi

    if [[ "$IS_CONTAINER" != true ]]; then
        touch "${_UFW_CONFIG_FILES[@]}"
        /usr/sbin/ufw "$@" || return $?
        touch "${_UFW_CONFIG_FILES[@]}"
    else
        _ufw_ensure_state_dir
        /usr/bin/touch "$_UFW_CONFIG_LIST"
        grep -v "^logging " "$_UFW_CONFIG_LIST" > "${_UFW_CONFIG_LIST}.tmp" 2>/dev/null || true
        /usr/bin/mv "${_UFW_CONFIG_LIST}.tmp" "$_UFW_CONFIG_LIST"
        echo "logging ${level}" >> "$_UFW_CONFIG_LIST"
    fi
}

# ── reset (command) ───────────────────────────────────────────────

_ufw_shim_reset_cmd() {
    if [[ "$IS_CONTAINER" != true ]]; then
        touch "${_UFW_CONFIG_FILES[@]}"
        /usr/sbin/ufw reset --force || return $?
        touch "${_UFW_CONFIG_FILES[@]}"
    else
        /usr/bin/rm -f "$_UFW_RULES_LIST" "$_UFW_DEFAULTS_LIST" "$_UFW_CONFIG_LIST"
    fi
}

# ── status ────────────────────────────────────────────────────────

_ufw_shim_status() {
    if [[ "$IS_CONTAINER" != true ]]; then
        /usr/sbin/ufw "$@"
        return $?
    fi

    # Container: emulate from declared state
    echo "=== UFW Declared State (container mode) ==="

    if [[ -f "$_UFW_CONFIG_LIST" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            echo "  $line"
        done < "$_UFW_CONFIG_LIST"
    fi

    if [[ -f "$_UFW_DEFAULTS_LIST" ]]; then
        echo ""
        echo "Defaults:"
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            echo "  $line"
        done < "$_UFW_DEFAULTS_LIST"
    fi

    if [[ -f "$_UFW_RULES_LIST" ]]; then
        echo ""
        echo "Rules:"
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            echo "  $line"
        done < "$_UFW_RULES_LIST"
    fi

    if [[ ! -f "$_UFW_RULES_LIST" && ! -f "$_UFW_DEFAULTS_LIST" && ! -f "$_UFW_CONFIG_LIST" ]]; then
        echo "  No firewall state declared."
    fi
}

# ── reload ────────────────────────────────────────────────────────

_ufw_shim_reload() {
    if [[ "$IS_CONTAINER" != true ]]; then
        /usr/sbin/ufw reload
        return $?
    fi
    # Container: no-op
}

# ── Build reset ───────────────────────────────────────────────────

# Called once at build start (provision/build.sh).
# Bootstrap: no-op — fs_shim_reset already cleared file-tracking state.
# Container: wipes structured state files for a clean rebuild.
ufw_shim_reset() {
    if [[ "$IS_CONTAINER" == true ]]; then
        /usr/bin/mkdir -p "$UFW_STATE_DIR"
        /usr/bin/rm -f "$_UFW_RULES_LIST" "$_UFW_DEFAULTS_LIST" "$_UFW_CONFIG_LIST"
    fi
}
