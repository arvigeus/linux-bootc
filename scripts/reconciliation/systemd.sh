#!/usr/bin/env bash
## Systemd service reconciliation
##
## Tracks enabled and masked units. Disabled/unmask removes entries
## (like dnf remove — if you want a service to stay off, mask it).
##
## State files use tab-separated format: unit<TAB>state<TAB>scope
##   services.list      — managed units (owned by build-time shim, read-only here)
##   services.base.list — baseline units (known but unmanaged, self-cleaning)
##
## Pre-reconciliation:  seed services.base.list from currently enabled/masked units
## Post-reconciliation: promote, clean stale, detect drift, prompt

SYSTEMD_STATE_DIR="${STATE_DIR}/systemd"
_SCTL_SERVICES_LIST="${SYSTEMD_STATE_DIR}/services.list"
_SCTL_BASE_LIST="${SYSTEMD_STATE_DIR}/services.base.list"

# ── Helpers ───────────────────────────────────────────────────────

# Query unit file states for a given scope.
# Outputs sorted unit<TAB>state<TAB>scope lines, filtered to enabled/masked.
_sctl_query_units() {
    local scope="$1"
    shift
    local -a scope_flags=("$@")
    /usr/bin/systemctl list-unit-files --no-pager --no-legend "${scope_flags[@]}" 2>/dev/null \
        | awk -v s="$scope" '$2 == "enabled" || $2 == "masked" { printf "%s\t%s\t%s\n", $1, $2, s }' \
        | sort -t$'\t' -k1,1
}

# Get the actual state of a single unit.
_sctl_get_unit_state() {
    local unit="$1"
    shift
    /usr/bin/systemctl is-enabled "$unit" "$@" 2>/dev/null || true
}

# ── Pre-reconciliation ────────────────────────────────────────────

reconcile_systemd_pre() {
    echo "=== Systemd Reconciliation (pre) ==="

    [[ -f "$_SCTL_BASE_LIST" ]] && return 0

    echo "No base state found. Seeding from currently active units..."
    mkdir -p "$SYSTEMD_STATE_DIR"

    local states=""
    states+=$(_sctl_query_units system)
    states+=$'\n'
    states+=$(_sctl_query_units global --global)
    if [[ -n "${SUDO_USER:-}" ]]; then
        states+=$'\n'
        states+=$(_sctl_query_units user --user)
    fi

    # Write non-empty lines
    if [[ -n "$states" ]]; then
        echo "$states" | grep -v '^$' > "$_SCTL_BASE_LIST" || touch "$_SCTL_BASE_LIST"
    else
        touch "$_SCTL_BASE_LIST"
    fi
    echo "  Seeded $(grep -c . "$_SCTL_BASE_LIST" 2>/dev/null || echo 0) units into services.base.list"
}

# ── Post-reconciliation ──────────────────────────────────────────

reconcile_systemd_post() {
    echo "=== Systemd Reconciliation (post) ==="

    # Safety: base.list should exist from pre-reconciliation
    if [[ ! -f "$_SCTL_BASE_LIST" ]]; then
        echo "WARNING: services.base.list missing — creating empty file."
        mkdir -p "$SYSTEMD_STATE_DIR"
        touch "$_SCTL_BASE_LIST"
    fi

    # Promote managed entries out of base
    if [[ -f "$_SCTL_SERVICES_LIST" ]]; then
        while IFS=$'\t' read -r unit _ scope; do
            [[ -n "$unit" ]] || continue
            if grep -q "^${unit}	[^	]*	${scope}$" "$_SCTL_BASE_LIST" 2>/dev/null; then
                grep -v "^${unit}	[^	]*	${scope}$" "$_SCTL_BASE_LIST" > "${_SCTL_BASE_LIST}.tmp" || true
                mv "${_SCTL_BASE_LIST}.tmp" "$_SCTL_BASE_LIST"
            fi
        done < "$_SCTL_SERVICES_LIST"
    fi

    # Clean stale base entries — remove units whose actual state no longer matches
    if [[ -s "$_SCTL_BASE_LIST" ]]; then
        local -a cleaned=()
        while IFS=$'\t' read -r unit base_state scope; do
            [[ -n "$unit" ]] || continue
            local -a scope_flags=()
            [[ "$scope" == "global" ]] && scope_flags=(--global)
            [[ "$scope" == "user" ]] && scope_flags=(--user)
            local actual
            actual=$(_sctl_get_unit_state "$unit" "${scope_flags[@]}")
            if [[ "$actual" == "$base_state" ]]; then
                cleaned+=("${unit}	${base_state}	${scope}")
            fi
        done < "$_SCTL_BASE_LIST"
        printf '%s\n' "${cleaned[@]+"${cleaned[@]}"}" > "$_SCTL_BASE_LIST"
    fi

    # Check managed units for drift
    local -a drifted=()
    if [[ -f "$_SCTL_SERVICES_LIST" ]]; then
        while IFS=$'\t' read -r unit declared_state scope; do
            [[ -n "$unit" ]] || continue
            local -a scope_flags=()
            [[ "$scope" == "global" ]] && scope_flags=(--global)
            [[ "$scope" == "user" ]] && scope_flags=(--user)
            local actual
            actual=$(_sctl_get_unit_state "$unit" "${scope_flags[@]}")
            if [[ "$actual" != "$declared_state" ]]; then
                drifted+=("${unit}	${declared_state}	${actual}	${scope}")
            fi
        done < "$_SCTL_SERVICES_LIST"
    fi

    # Collect known units for untracked detection
    local -a known_entries=()
    if [[ -f "$_SCTL_SERVICES_LIST" ]]; then
        while IFS=$'\t' read -r unit _ scope; do
            [[ -n "$unit" ]] && known_entries+=("${unit}	${scope}")
        done < "$_SCTL_SERVICES_LIST"
    fi
    while IFS=$'\t' read -r unit _ scope; do
        [[ -n "$unit" ]] && known_entries+=("${unit}	${scope}")
    done < "$_SCTL_BASE_LIST"

    # Find untracked enabled/masked units across all scopes
    local -a untracked=()
    local scope
    for scope in system global user; do
        local -a scope_flags=()
        [[ "$scope" == "global" ]] && scope_flags=(--global)
        [[ "$scope" == "user" ]] && { [[ -n "${SUDO_USER:-}" ]] || continue; scope_flags=(--user); }
        while IFS=$'\t' read -r unit state _; do
            [[ -n "$unit" ]] || continue
            local key="${unit}	${scope}"
            local found=false
            for known in "${known_entries[@]+"${known_entries[@]}"}"; do
                if [[ "$known" == "$key" ]]; then
                    found=true
                    break
                fi
            done
            $found || untracked+=("${unit}	${state}	${scope}")
        done < <(_sctl_query_units "$scope" "${scope_flags[@]}")
    done

    if [[ ${#drifted[@]} -eq 0 && ${#untracked[@]} -eq 0 ]]; then
        echo "Services match declared state."
        return 0
    fi

    # Prompt for drifted managed units
    if [[ ${#drifted[@]} -gt 0 ]]; then
        echo ""
        echo "Drifted managed units (actual state differs from declared):"
        for entry in "${drifted[@]}"; do
            IFS=$'\t' read -r unit declared actual scope <<< "$entry"
            echo "  ${unit} (${scope}): declared=${declared}, actual=${actual}"
        done
        echo ""
        echo "  [r] Restore declared state"
        echo "  [i] Ignore"
        read -rp "Choice: " choice
        case "$choice" in
            [Rr])
                for entry in "${drifted[@]}"; do
                    IFS=$'\t' read -r unit declared _ scope <<< "$entry"
                    local -a sf=()
                    [[ "$scope" == "global" ]] && sf=(--global)
                    [[ "$scope" == "user" ]] && sf=(--user)
                    case "$declared" in
                        enabled) /usr/bin/systemctl enable "${sf[@]}" "$unit" ;;
                        masked)  /usr/bin/systemctl mask "${sf[@]}" "$unit" ;;
                    esac
                done
                echo "  Restored."
                ;;
            *)
                echo "  Ignored."
                ;;
        esac
    fi

    # Prompt for untracked units
    if [[ ${#untracked[@]} -gt 0 ]]; then
        echo ""
        echo "Untracked units (not declared or in baseline):"
        for entry in "${untracked[@]}"; do
            IFS=$'\t' read -r unit state scope <<< "$entry"
            echo "  ${unit} (${scope}, ${state})"
        done
        echo ""
        echo "  [b] Add to baseline (keep but don't manage)"
        echo "  [i] Ignore (will be asked again next time)"
        read -rp "Choice: " choice
        case "$choice" in
            [Bb])
                for entry in "${untracked[@]}"; do
                    echo "$entry" >> "$_SCTL_BASE_LIST"
                done
                echo "  Added ${#untracked[@]} unit(s) to baseline."
                ;;
            *)
                echo "  Ignored."
                ;;
        esac
    fi
}

# ── Run ───────────────────────────────────────────────────────────

case "$MODE" in
    pre)  reconcile_systemd_pre ;;
    post) reconcile_systemd_post ;;
esac
