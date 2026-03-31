#!/usr/bin/env bash
## Privilege de-escalation helper
##
## When running under sudo (SUDO_USER is set), drops back to the
## invoking user. Otherwise runs the command as-is.

run_unprivileged() {
	if [[ -n "${SUDO_USER:-}" ]]; then
		sudo -u "$SUDO_USER" "$@"
	else
		"$@"
	fi
}
