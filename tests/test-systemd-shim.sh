#!/usr/bin/env bash
## Tests for provision/shims/systemd.sh
##
## Verifies argument parsing, state recording, --now stripping, scope handling,
## disallowed commands, and container vs bootstrap behavior.
## Mocks /usr/bin/systemctl to avoid touching real system state.
##
## Usage:  bash tests/test-systemd-shim.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
STATE_DIR="${TEST_DIR}/state"

mkdir -p "$STATE_DIR"

# ── Test framework ─────────────────────────────────────────────────

_pass=0 _fail=0 _total=0

pass() {
	_pass=$((_pass + 1))
	_total=$((_total + 1))
	echo "  ok $_total - $1"
}
fail() {
	_fail=$((_fail + 1))
	_total=$((_total + 1))
	echo "  not ok $_total - $1"
	echo "    $2"
}

assert_file_exists() { [[ -e "$1" ]] && pass "$2" || fail "$2" "expected $1 to exist"; }
assert_file_missing() { [[ ! -e "$1" ]] && pass "$2" || fail "$2" "expected $1 to NOT exist"; }

# Check that a file contains a specific line
assert_has_line() {
	local file="$1" line="$2" label="$3"
	if [[ -f "$file" ]] && grep -qxF -- "$line" "$file" 2>/dev/null; then
		pass "$label"
	else
		fail "$label" "expected line '$line' in $file, got: $(cat "$file" 2>/dev/null || echo "<missing>")"
	fi
}

# Check that a file does NOT contain a specific line
assert_no_line() {
	local file="$1" line="$2" label="$3"
	if [[ ! -f "$file" ]] || ! grep -qxF -- "$line" "$file" 2>/dev/null; then
		pass "$label"
	else
		fail "$label" "expected line '$line' NOT in $file"
	fi
}

# Check that the mock log contains a specific entry
assert_mock_called() {
	local expected="$1" label="$2"
	if grep -qF -- "$expected" "$MOCK_LOG" 2>/dev/null; then
		pass "$label"
	else
		fail "$label" "expected mock call containing '$expected', got: $(cat "$MOCK_LOG" 2>/dev/null || echo "<empty>")"
	fi
}

# Check that the mock log does NOT contain a specific entry
assert_mock_not_called() {
	local expected="$1" label="$2"
	if ! grep -qF -- "$expected" "$MOCK_LOG" 2>/dev/null; then
		pass "$label"
	else
		fail "$label" "expected mock NOT called with '$expected'"
	fi
}

# Check line count in a file
assert_line_count() {
	local file="$1" expected="$2" label="$3"
	local actual=0
	[[ -f "$file" ]] && { actual=$(grep -c . "$file" 2>/dev/null) || actual=0; }
	if [[ "$actual" -eq "$expected" ]]; then
		pass "$label"
	else
		fail "$label" "expected $expected lines, got $actual"
	fi
}

# ── Source shim and override paths ─────────────────────────────────

source "${SCRIPT_DIR}/provision/shims/systemd.sh"

# Override state dir to our temp location
SYSTEMD_STATE_DIR="$STATE_DIR"
_SCTL_SERVICES_LIST="${STATE_DIR}/services.list"

# Mock /usr/bin/systemctl — records calls to a log file
MOCK_LOG="${TEST_DIR}/mock.log"
/usr/bin/systemctl() { echo "$*" >>"$MOCK_LOG"; }

# Start in bootstrap mode
IS_CONTAINER=false

# Helper to reset state between test groups
reset_state() {
	IS_CONTAINER=false
	/usr/bin/rm -rf "$STATE_DIR"
	/usr/bin/mkdir -p "$STATE_DIR"
	: >"$MOCK_LOG"
}

LIST="$_SCTL_SERVICES_LIST"

# ═══════════════════════════════════════════════════════════════════
echo "TAP version 13"
echo "# systemd.sh shim tests"
echo ""

# ── Test: enable single service ──────────────────────────────────
echo "# enable: single service"
reset_state

systemctl enable foo.service

assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tsystem')" \
	"enable: records enabled state"
assert_mock_called "enable foo.service" \
	"enable: calls real binary"

# ── Test: enable without .service suffix (normalization) ─────────
echo "# enable: bare name normalization"
reset_state

systemctl enable foo

assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tsystem')" \
	"enable bare: normalized to foo.service"

# ── Test: enable with .timer suffix (preserved) ─────────────────
echo "# enable: timer suffix preserved"
reset_state

systemctl enable foo.timer

assert_has_line "$LIST" "$(printf 'foo.timer\tenabled\tsystem')" \
	"enable timer: .timer preserved"

# ── Test: enable template unit ───────────────────────────────────
echo "# enable: template unit"
reset_state

systemctl enable foo@bar.service

assert_has_line "$LIST" "$(printf 'foo@bar.service\tenabled\tsystem')" \
	"enable template: foo@bar.service recorded"

# ── Test: enable multiple units ──────────────────────────────────
echo "# enable: multiple units"
reset_state

systemctl enable a.service b.timer

assert_has_line "$LIST" "$(printf 'a.service\tenabled\tsystem')" \
	"enable multi: a.service recorded"
assert_has_line "$LIST" "$(printf 'b.timer\tenabled\tsystem')" \
	"enable multi: b.timer recorded"

# ── Test: mask records masked state ──────────────────────────────
echo "# mask: records masked"
reset_state

systemctl mask foo.service

assert_has_line "$LIST" "$(printf 'foo.service\tmasked\tsystem')" \
	"mask: records masked state"

# ── Test: disable removes entry ──────────────────────────────────
echo "# disable: removes entry"
reset_state

systemctl enable foo.service
systemctl disable foo.service

assert_no_line "$LIST" "$(printf 'foo.service\tenabled\tsystem')" \
	"disable: enabled entry removed"
assert_line_count "$LIST" 0 \
	"disable: list is empty"

# ── Test: unmask removes entry ───────────────────────────────────
echo "# unmask: removes entry"
reset_state

systemctl mask foo.service
systemctl unmask foo.service

assert_no_line "$LIST" "$(printf 'foo.service\tmasked\tsystem')" \
	"unmask: masked entry removed"

# ── Test: enable then mask replaces entry ────────────────────────
echo "# enable then mask: replaces"
reset_state

systemctl enable foo.service
systemctl mask foo.service

assert_no_line "$LIST" "$(printf 'foo.service\tenabled\tsystem')" \
	"mask replaces: old enabled entry gone"
assert_has_line "$LIST" "$(printf 'foo.service\tmasked\tsystem')" \
	"mask replaces: new masked entry present"
assert_line_count "$LIST" 1 \
	"mask replaces: exactly one entry"

# ── Test: enable --now in bootstrap ──────────────────────────────
echo "# enable --now: bootstrap passes --now"
reset_state

systemctl enable --now foo.service

assert_mock_called "--now" \
	"enable --now bootstrap: --now passed to binary"
assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tsystem')" \
	"enable --now bootstrap: records enabled"

# ── Test: enable --now in container (strips --now) ───────────────
echo "# enable --now: container strips --now"
reset_state
IS_CONTAINER=true

systemctl enable --now foo.service

assert_mock_not_called "--now" \
	"enable --now container: --now stripped"
assert_mock_called "enable foo.service" \
	"enable --now container: enable still called"
assert_file_missing "$LIST" \
	"enable --now container: no state recorded"

IS_CONTAINER=false

# ── Test: --now before subcommand ────────────────────────────────
echo "# flags before subcommand: --now enable"
reset_state
IS_CONTAINER=true

systemctl --now enable foo.service

assert_mock_not_called "--now" \
	"flags-before: --now stripped even when before subcommand"
assert_mock_called "enable foo.service" \
	"flags-before: enable still called"

IS_CONTAINER=false

# ── Test: --global enable ────────────────────────────────────────
echo "# --global enable: records with global scope"
reset_state

systemctl --global enable foo.service

assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tglobal')" \
	"--global: recorded with global scope"

# ── Test: --global enable in container ───────────────────────────
echo "# --global enable: container executes, no recording"
reset_state
IS_CONTAINER=true

systemctl --global enable foo.service

assert_mock_called "--global enable foo.service" \
	"--global container: real binary called"
assert_file_missing "$LIST" \
	"--global container: no state recorded"

IS_CONTAINER=false

# ── Test: --user enable in bootstrap ─────────────────────────────
echo "# --user enable: bootstrap executes + records"
reset_state

systemctl --user enable foo.service

assert_mock_called "--user enable foo.service" \
	"--user bootstrap: real binary called"
assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tuser')" \
	"--user bootstrap: recorded with user scope"

# ── Test: --user enable in container (no execution, records) ─────
echo "# --user enable: container records only"
reset_state
IS_CONTAINER=true

systemctl --user enable foo.service

assert_mock_not_called "enable" \
	"--user container: binary NOT called"
assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tuser')" \
	"--user container: recorded with user scope"

IS_CONTAINER=false

# ── Test: --user enable --now in container ───────────────────────
echo "# --user enable --now: container records enabled (no --now effect)"
reset_state
IS_CONTAINER=true

systemctl --user enable --now foo.timer

assert_mock_not_called "enable" \
	"--user --now container: binary NOT called"
assert_has_line "$LIST" "$(printf 'foo.timer\tenabled\tuser')" \
	"--user --now container: records enabled"

IS_CONTAINER=false

# ── Test: mixed scopes in single file ────────────────────────────
echo "# mixed scopes: all in one file"
reset_state

systemctl enable a.service
systemctl --global enable b.timer
systemctl --user mask c.service

assert_has_line "$LIST" "$(printf 'a.service\tenabled\tsystem')" \
	"mixed: system entry present"
assert_has_line "$LIST" "$(printf 'b.timer\tenabled\tglobal')" \
	"mixed: global entry present"
assert_has_line "$LIST" "$(printf 'c.service\tmasked\tuser')" \
	"mixed: user entry present"
assert_line_count "$LIST" 3 \
	"mixed: exactly three entries"

# ── Test: disable only removes matching scope ────────────────────
echo "# disable: respects scope"
reset_state

systemctl enable foo.service
systemctl --user enable foo.service
systemctl disable foo.service

assert_no_line "$LIST" "$(printf 'foo.service\tenabled\tsystem')" \
	"disable scope: system entry removed"
assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tuser')" \
	"disable scope: user entry preserved"

# ── Test: start in bootstrap ────────────────────────────────────
echo "# start: bootstrap executes"
reset_state

systemctl start foo.service

assert_mock_called "start foo.service" \
	"start bootstrap: real binary called"
assert_file_missing "$LIST" \
	"start bootstrap: no state recorded"

# ── Test: start in container (skipped) ───────────────────────────
echo "# start: container skips"
reset_state
IS_CONTAINER=true

systemctl start foo.service

assert_mock_not_called "start" \
	"start container: binary NOT called"

IS_CONTAINER=false

# ── Test: stop errors ────────────────────────────────────────────
echo "# stop: hard error"
reset_state

if systemctl stop foo.service 2>/dev/null; then
	fail "stop: should error" "returned 0"
else
	pass "stop: returns non-zero"
fi
assert_mock_not_called "stop" \
	"stop: binary NOT called"

# ── Test: restart errors ─────────────────────────────────────────
echo "# restart: hard error"
reset_state

if systemctl restart foo.service 2>/dev/null; then
	fail "restart: should error" "returned 0"
else
	pass "restart: returns non-zero"
fi

# ── Test: reload errors ─────────────────────────────────────────
echo "# reload: hard error"
reset_state

if systemctl reload foo.service 2>/dev/null; then
	fail "reload: should error" "returned 0"
else
	pass "reload: returns non-zero"
fi

# ── Test: try-restart errors ─────────────────────────────────────
echo "# try-restart: hard error"
reset_state

if systemctl try-restart foo.service 2>/dev/null; then
	fail "try-restart: should error" "returned 0"
else
	pass "try-restart: returns non-zero"
fi

# ── Test: reload-or-restart errors ───────────────────────────────
echo "# reload-or-restart: hard error"
reset_state

if systemctl reload-or-restart foo.service 2>/dev/null; then
	fail "reload-or-restart: should error" "returned 0"
else
	pass "reload-or-restart: returns non-zero"
fi

# ── Test: stop errors in container too ───────────────────────────
echo "# stop: hard error in container too"
reset_state
IS_CONTAINER=true

if systemctl stop foo.service 2>/dev/null; then
	fail "stop container: should error" "returned 0"
else
	pass "stop container: returns non-zero"
fi

IS_CONTAINER=false

# ── Test: daemon-reload in bootstrap ─────────────────────────────
echo "# daemon-reload: bootstrap executes"
reset_state

systemctl daemon-reload

assert_mock_called "daemon-reload" \
	"daemon-reload bootstrap: real binary called"

# ── Test: daemon-reload in container (skipped) ───────────────────
echo "# daemon-reload: container skips"
reset_state
IS_CONTAINER=true

systemctl daemon-reload

assert_mock_not_called "daemon-reload" \
	"daemon-reload container: binary NOT called"

IS_CONTAINER=false

# ── Test: value-taking flags don't swallow unit names ────────────
echo "# parser: value-taking flags"
reset_state

systemctl --type service enable foo.service

assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tsystem')" \
	"parser: --type doesn't swallow unit name"

# ── Test: --type=value form ──────────────────────────────────────
echo "# parser: --type=value form"
reset_state

systemctl --type=service enable foo.service

assert_has_line "$LIST" "$(printf 'foo.service\tenabled\tsystem')" \
	"parser: --type=value doesn't break"

# ── Test: container mode skips recording for --system ────────────
echo "# container: --system no recording"
reset_state
IS_CONTAINER=true

systemctl enable foo.service

assert_mock_called "enable foo.service" \
	"container system: real binary called"
assert_file_missing "$LIST" \
	"container system: no state recorded"

IS_CONTAINER=false

# ── Test: systemd_shim_reset clears list, keeps base ─────────────
echo "# systemd_shim_reset: clears services.list, keeps .base.list"
reset_state

# Create managed and base lists
printf 'foo.service\tenabled\tsystem\n' >"$LIST"
printf 'bar.service\tenabled\tsystem\n' >"${STATE_DIR}/services.base.list"

systemd_shim_reset

assert_file_missing "$LIST" \
	"reset: services.list cleared"
assert_file_exists "${STATE_DIR}/services.base.list" \
	"reset: services.base.list preserved"
assert_has_line "${STATE_DIR}/services.base.list" "$(printf 'bar.service\tenabled\tsystem')" \
	"reset: base.list content intact"

# ── Test: pass-through for unknown subcommands ───────────────────
echo "# pass-through: unknown subcommands"
reset_state

systemctl status foo.service

assert_mock_called "status foo.service" \
	"pass-through: status forwarded to binary"

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "1..${_total}"
echo "# pass: $_pass"
echo "# fail: $_fail"

# Cleanup
/usr/bin/rm -rf "$TEST_DIR"

[[ $_fail -eq 0 ]] && exit 0 || exit 1
