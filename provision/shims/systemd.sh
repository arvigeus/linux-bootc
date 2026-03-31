#!/usr/bin/env bash
## Systemd build-time shim
##
## Shadows `/usr/bin/systemctl` as a bash function so that modules can
## write natural-looking systemctl commands. The shim handles dual-mode
## operation and records declared service state for reconciliation.
##
## Subcommand behavior:
##
##   enable / mask
##     --system/--global:  Execute in both modes (file ops).
##                         Container: strip --now, skip recording.
##                         Bootstrap: execute + record state.
##     --user:             Container: record only (deferred to post-deploy).
##                         Bootstrap: execute + record.
##
##   disable / unmask      Execute in both modes. Remove from services.list
##                         (like dnf remove — no longer declaring a state).
##
##   start                 Container: skip (service starts on boot).
##                         Bootstrap: execute, no recording.
##
##   stop / restart / reload / try-restart / reload-or-restart
##                         Hard error in both modes — non-declarative,
##                         cannot ensure same end state.
##
##   daemon-reload / daemon-reexec
##                         Container: skip (no daemon).
##                         Bootstrap: execute, no recording.
##
##   Everything else       Pass through to /usr/bin/systemctl.
##
## Generated files:
##   /usr/share/system-state.d/systemd/services.list      — managed units
##   /usr/share/system-state.d/systemd/services.base.list — baseline units
##
## Line format: unit<TAB>state<TAB>scope
##   fwupd-refresh.timer	enabled	system
##   foo.service	masked	user
##
## Only 'enabled' and 'masked' are tracked. 'disable' and 'unmask'
## remove entries — if you want a service to stay off, mask it.
##
## Bypass the shim with the full path: /usr/bin/systemctl

SYSTEMD_STATE_DIR="/usr/share/system-state.d/systemd"
_SCTL_SERVICES_LIST="${SYSTEMD_STATE_DIR}/services.list"

# ── Argument parser ───────────────────────────────────────────────
#
# Separates flags, subcommand, and unit names from systemctl args.
#
# Outputs (globals, reused across calls):
#   _sctl_scope        — "system" (default), "global", or "user"
#   _sctl_subcommand   — the subcommand (enable, start, etc.)
#   _sctl_has_now      — true if --now is present
#   _sctl_units=()     — unit name arguments
#   _sctl_flags=()     — all flag tokens (preserved for pass-through)

_sctl_parse_args() {
	_sctl_scope="system"
	_sctl_subcommand=""
	_sctl_has_now=false
	_sctl_units=()
	_sctl_flags=()

	# Value-taking flags (long and short forms)
	local vlong="type|state|property|root|runtime|output|signal|kill-who|host|machine"
	local vshort="tpnosHM"

	local end_of_flags=false
	local skip_next=false
	local found_subcommand=false

	for arg in "$@"; do
		if $skip_next; then
			_sctl_flags+=("$arg")
			skip_next=false
			continue
		fi

		if $end_of_flags; then
			if ! $found_subcommand; then
				_sctl_subcommand="$arg"
				found_subcommand=true
			else
				_sctl_units+=("$arg")
			fi
			continue
		fi

		case "$arg" in
		--)
			end_of_flags=true
			;;
		--now)
			_sctl_has_now=true
			_sctl_flags+=("$arg")
			;;
		--global)
			_sctl_scope="global"
			_sctl_flags+=("$arg")
			;;
		--user)
			_sctl_scope="user"
			_sctl_flags+=("$arg")
			;;
		--system)
			_sctl_scope="system"
			_sctl_flags+=("$arg")
			;;
		--*=*)
			_sctl_flags+=("$arg")
			;;
		--*)
			local flag_name="${arg#--}"
			_sctl_flags+=("$arg")
			if [[ "|${vlong}|" == *"|${flag_name}|"* ]]; then
				skip_next=true
			fi
			;;
		-?*)
			_sctl_flags+=("$arg")
			local chars="${arg#-}"
			local last="${chars: -1}"
			if [[ "$vshort" == *"$last"* ]]; then
				skip_next=true
			fi
			;;
		*)
			if ! $found_subcommand; then
				_sctl_subcommand="$arg"
				found_subcommand=true
			else
				_sctl_units+=("$arg")
			fi
			;;
		esac
	done
}

# ── Unit normalization ────────────────────────────────────────────

# Append .service suffix when the name has no dot (matches systemd behavior).
_sctl_normalize_unit() {
	local u="$1"
	[[ "$u" == *.* ]] && echo "$u" || echo "${u}.service"
}

# ── State recording ──────────────────────────────────────────────

# Add a unit to services.list (enable/mask).
_sctl_record_add() {
	local unit="$1" state="$2" scope="$3"
	/usr/bin/mkdir -p "$SYSTEMD_STATE_DIR"
	/usr/bin/touch "$_SCTL_SERVICES_LIST"

	# Remove any existing entry for this unit+scope
	_sctl_record_remove "$unit" "$scope"

	printf '%s\t%s\t%s\n' "$unit" "$state" "$scope" >>"$_SCTL_SERVICES_LIST"
}

# Remove a unit from services.list (disable/unmask).
_sctl_record_remove() {
	local unit="$1" scope="$2"
	[[ -f "$_SCTL_SERVICES_LIST" ]] || return 0

	if grep -q "^${unit}	[^	]*	${scope}$" "$_SCTL_SERVICES_LIST" 2>/dev/null; then
		grep -v "^${unit}	[^	]*	${scope}$" "$_SCTL_SERVICES_LIST" >"${_SCTL_SERVICES_LIST}.tmp" || true
		/usr/bin/mv "${_SCTL_SERVICES_LIST}.tmp" "$_SCTL_SERVICES_LIST"
	fi
}

# ── --now stripping ──────────────────────────────────────────────

# Rebuild args without --now for container execution.
_sctl_strip_now() {
	local -a filtered=()
	for arg in "$@"; do
		[[ "$arg" == "--now" ]] && continue
		filtered+=("$arg")
	done
	/usr/bin/systemctl "${filtered[@]}"
}

# ── Shimmed command ──────────────────────────────────────────────

systemctl() {
	_sctl_parse_args "$@"

	case "$_sctl_subcommand" in
	enable | mask)
		_sctl_shim_add_state "$@"
		;;
	disable | unmask)
		_sctl_shim_remove_state "$@"
		;;
	start)
		_sctl_shim_start "$@"
		;;
	stop | restart | reload | try-restart | reload-or-restart)
		_sctl_shim_disallowed "$@"
		;;
	daemon-reload | daemon-reexec)
		_sctl_shim_daemon "$@"
		;;
	*)
		/usr/bin/systemctl "$@"
		;;
	esac
}

# ── enable / mask ────────────────────────────────────────────────

_sctl_shim_add_state() {
	local state_label
	case "$_sctl_subcommand" in
	enable) state_label="enabled" ;;
	mask) state_label="masked" ;;
	esac

	if [[ "$IS_CONTAINER" == true ]]; then
		if [[ "$_sctl_scope" == "user" ]]; then
			# Container + --user: record only, defer to post-deploy
			local unit
			for unit in "${_sctl_units[@]}"; do
				unit=$(_sctl_normalize_unit "$unit")
				_sctl_record_add "$unit" "$state_label" user
			done
			return 0
		fi

		# Container + --system/--global: execute (file ops work), strip --now
		if $_sctl_has_now; then
			_sctl_strip_now "$@"
		else
			/usr/bin/systemctl "$@"
		fi
		return $?
	fi

	# Bootstrap: execute the full command
	/usr/bin/systemctl "$@" || return $?

	# Record state
	local unit
	for unit in "${_sctl_units[@]}"; do
		unit=$(_sctl_normalize_unit "$unit")
		_sctl_record_add "$unit" "$state_label" "$_sctl_scope"
	done
}

# ── disable / unmask ─────────────────────────────────────────────

_sctl_shim_remove_state() {
	if [[ "$IS_CONTAINER" == true ]]; then
		if [[ "$_sctl_scope" == "user" ]]; then
			# Container + --user: remove from list (for post-deploy)
			local unit
			for unit in "${_sctl_units[@]}"; do
				unit=$(_sctl_normalize_unit "$unit")
				_sctl_record_remove "$unit" user
			done
			return 0
		fi

		# Container + --system/--global: execute (file ops work), strip --now
		if $_sctl_has_now; then
			_sctl_strip_now "$@"
		else
			/usr/bin/systemctl "$@"
		fi
		return $?
	fi

	# Bootstrap: execute the full command
	/usr/bin/systemctl "$@" || return $?

	# Remove from state
	local unit
	for unit in "${_sctl_units[@]}"; do
		unit=$(_sctl_normalize_unit "$unit")
		_sctl_record_remove "$unit" "$_sctl_scope"
	done
}

# ── start ────────────────────────────────────────────────────────

_sctl_shim_start() {
	if [[ "$IS_CONTAINER" == true ]]; then
		# Service will start on boot — skip silently
		return 0
	fi

	# Bootstrap: execute, no recording (runtime-only)
	/usr/bin/systemctl "$@"
}

# ── stop / restart / reload / try-restart / reload-or-restart ────

_sctl_shim_disallowed() {
	echo "ERROR: systemd shim: '${_sctl_subcommand}' is not allowed in build scripts." >&2
	echo "  These commands are non-declarative and cannot ensure the same" >&2
	echo "  end state across container and bootstrap modes." >&2
	echo "  Use 'enable' for persistent state; 'start' for boot-time activation." >&2
	return 1
}

# ── daemon-reload / daemon-reexec ────────────────────────────────

_sctl_shim_daemon() {
	if [[ "$IS_CONTAINER" == true ]]; then
		return 0
	fi

	/usr/bin/systemctl "$@"
}

# ── Reset ────────────────────────────────────────────────────────

# Called once at build start. Wipes managed list for a clean rebuild,
# preserves .base.list.
systemd_shim_reset() {
	/usr/bin/mkdir -p "$SYSTEMD_STATE_DIR"
	/usr/bin/rm -f "$_SCTL_SERVICES_LIST"
}
