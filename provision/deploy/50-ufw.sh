#!/usr/bin/env bash
## Post-deploy: apply UFW firewall rules
##
## Container only. Reads structured state files written by the build-time shim
## and configures the firewall on first boot.
##
## State files (written by build-time shim):
##   /usr/share/system-state.d/ufw/defaults.list  — default policies
##   /usr/share/system-state.d/ufw/rules.list     — declared rules
##   /usr/share/system-state.d/ufw/config.list    — enabled/disabled, logging
##
## Applied in order: defaults → rules → config (enable/disable, logging).
## Commands are idempotent — re-running is safe if a previous deploy was interrupted.
set -euo pipefail

UFW_STATE_DIR="/usr/share/system-state.d/ufw"

[[ -d "$UFW_STATE_DIR" ]] || exit 0

# Apply default policies
if [[ -f "${UFW_STATE_DIR}/defaults.list" ]]; then
	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		echo ":: ufw default $line"
		# shellcheck disable=SC2086
		ufw default $line || echo "WARNING: 'ufw default $line' failed" >&2
	done <"${UFW_STATE_DIR}/defaults.list"
fi

# Apply rules
if [[ -f "${UFW_STATE_DIR}/rules.list" ]]; then
	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		echo ":: ufw $line"
		# shellcheck disable=SC2086
		ufw $line || echo "WARNING: 'ufw $line' failed (may already be applied)" >&2
	done <"${UFW_STATE_DIR}/rules.list"
fi

# Apply config (enable/disable, logging)
if [[ -f "${UFW_STATE_DIR}/config.list" ]]; then
	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		case "$line" in
		enabled) ufw --force enable || echo "WARNING: 'ufw enable' failed" >&2 ;;
		disabled) ufw disable || echo "WARNING: 'ufw disable' failed" >&2 ;;
		logging\ *) ufw logging "${line#logging }" || echo "WARNING: 'ufw logging ...' failed" >&2 ;;
		esac
	done <"${UFW_STATE_DIR}/config.list"
fi
