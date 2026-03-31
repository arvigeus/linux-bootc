#!/usr/bin/env bash
## Tests for provision/shims/ufw.sh
##
## Verifies container state recording, bootstrap execution + snapshotting,
## status emulation, and command dispatch.
##
## Bootstrap mode: checks that real ufw is called and config files are
##   snapshotted (no structured files written).
## Container mode: checks that structured files are written and real ufw
##   is never called.
##
## Usage:  bash tests/test-ufw-shim.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
STATE_DIR="${TEST_DIR}/state"

mkdir -p "$STATE_DIR"

# ── Test framework ─────────────────────────────────────────────────

_pass=0 _fail=0 _total=0

pass() { _pass=$(( _pass + 1 )); _total=$(( _total + 1 )); echo "  ok $_total - $1"; }
fail() { _fail=$(( _fail + 1 )); _total=$(( _total + 1 )); echo "  not ok $_total - $1"; echo "    $2"; }

assert_file_exists()  { [[ -e "$1" ]] && pass "$2" || fail "$2" "expected $1 to exist"; }
assert_file_missing() { [[ ! -e "$1" ]] && pass "$2" || fail "$2" "expected $1 to NOT exist"; }

assert_has_line() {
    local file="$1" line="$2" label="$3"
    if [[ -f "$file" ]] && grep -qxF -- "$line" "$file" 2>/dev/null; then
        pass "$label"
    else
        fail "$label" "expected line '$line' in $file, got: $(cat "$file" 2>/dev/null || echo "<missing>")"
    fi
}

assert_no_line() {
    local file="$1" line="$2" label="$3"
    if [[ ! -f "$file" ]] || ! grep -qxF -- "$line" "$file" 2>/dev/null; then
        pass "$label"
    else
        fail "$label" "expected line '$line' NOT in $file"
    fi
}

assert_mock_called() {
    local expected="$1" label="$2"
    if grep -qF -- "$expected" "$MOCK_LOG" 2>/dev/null; then
        pass "$label"
    else
        fail "$label" "expected mock call containing '$expected', got: $(cat "$MOCK_LOG" 2>/dev/null || echo "<empty>")"
    fi
}

assert_mock_not_called() {
    local expected="$1" label="$2"
    if ! grep -qF -- "$expected" "$MOCK_LOG" 2>/dev/null; then
        pass "$label"
    else
        fail "$label" "expected mock NOT called with '$expected'"
    fi
}

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

assert_output_contains() {
    local output="$1" expected="$2" label="$3"
    if echo "$output" | grep -qF -- "$expected"; then
        pass "$label"
    else
        fail "$label" "expected output containing '$expected', got: $output"
    fi
}

# ── Source shim ────────────────────────────────────────────────────

# Stub the touch shim's backing store so we can verify backup/record behaviour.
# The real touch shim calls _fs_backup_original + _fs_record_state internally;
# here we just track which files touch was called on and confirm the sandwich.
TOUCH_LOG="${TEST_DIR}/touch.log"
touch() { echo "$*" >> "$TOUCH_LOG"; /usr/bin/touch "$@"; }

source "${SCRIPT_DIR}/provision/shims/ufw.sh"

# Override state dir and config file paths to temp locations
UFW_STATE_DIR="$STATE_DIR"
_UFW_RULES_LIST="${STATE_DIR}/rules.list"
_UFW_DEFAULTS_LIST="${STATE_DIR}/defaults.list"
_UFW_CONFIG_LIST="${STATE_DIR}/config.list"

FAKE_UFW_DIR="${TEST_DIR}/etc/ufw"
/usr/bin/mkdir -p "$FAKE_UFW_DIR"
_UFW_CONFIG_FILES=(
    "${FAKE_UFW_DIR}/user.rules"
    "${FAKE_UFW_DIR}/user6.rules"
    "${FAKE_UFW_DIR}/ufw.conf"
)

# Mock /usr/sbin/ufw — records calls to a log file
MOCK_LOG="${TEST_DIR}/mock.log"
/usr/sbin/ufw() { echo "$*" >> "$MOCK_LOG"; }

# Start in bootstrap mode
IS_CONTAINER=false

# Helper to reset state between test groups
reset_state() {
    IS_CONTAINER=false
    /usr/bin/rm -rf "$STATE_DIR"
    /usr/bin/mkdir -p "$STATE_DIR"
    : > "$MOCK_LOG"
    : > "$TOUCH_LOG"
}

assert_touch_called() {
    local label="$1"
    if [[ -s "$TOUCH_LOG" ]]; then
        pass "$label"
    else
        fail "$label" "expected touch to be called, but touch.log is empty"
    fi
}

assert_touch_count() {
    local expected="$1" label="$2"
    local actual
    actual=$(grep -c "" "$TOUCH_LOG" 2>/dev/null || echo 0)
    if [[ "$actual" -eq "$expected" ]]; then
        pass "$label"
    else
        fail "$label" "expected $expected touch calls, got $actual"
    fi
}

RULES="$_UFW_RULES_LIST"
DEFAULTS="$_UFW_DEFAULTS_LIST"
CONFIG="$_UFW_CONFIG_LIST"

# ═══════════════════════════════════════════════════════════════════
echo "TAP version 13"
echo "# ufw.sh shim tests"
echo ""

# ── Bootstrap: allow ────────────────────────────────────────────────
echo "# bootstrap: allow executes with touch sandwich, no structured files"
reset_state

ufw allow 22/tcp

assert_mock_called "allow 22/tcp" "bootstrap allow: calls real binary"
assert_touch_count 2              "bootstrap allow: touch called before and after"
assert_file_missing "$RULES"    "bootstrap allow: no rules.list written"
assert_file_missing "$DEFAULTS" "bootstrap allow: no defaults.list written"
assert_file_missing "$CONFIG"   "bootstrap allow: no config.list written"

# ── Bootstrap: deny ─────────────────────────────────────────────────
echo "# bootstrap: deny executes with touch sandwich"
reset_state

ufw deny from 10.0.0.0/8

assert_mock_called "deny from 10.0.0.0/8" "bootstrap deny: calls real binary"
assert_touch_count 2 "bootstrap deny: touch sandwich called"

# ── Bootstrap: default ──────────────────────────────────────────────
echo "# bootstrap: default executes with touch sandwich"
reset_state

ufw default deny incoming

assert_mock_called "default deny incoming" "bootstrap default: calls real binary"
assert_touch_count 2 "bootstrap default: touch sandwich called"
assert_file_missing "$DEFAULTS" "bootstrap default: no defaults.list written"

# ── Bootstrap: enable ───────────────────────────────────────────────
echo "# bootstrap: enable executes with touch sandwich"
reset_state

ufw enable

assert_mock_called "enable" "bootstrap enable: calls real binary"
assert_touch_count 2 "bootstrap enable: touch sandwich called"
assert_file_missing "$CONFIG" "bootstrap enable: no config.list written"

# ── Bootstrap: logging ──────────────────────────────────────────────
echo "# bootstrap: logging executes with touch sandwich"
reset_state

ufw logging low

assert_mock_called "logging low" "bootstrap logging: calls real binary"
assert_touch_count 2 "bootstrap logging: touch sandwich called"
assert_file_missing "$CONFIG" "bootstrap logging: no config.list written"

# ── Bootstrap: insert ───────────────────────────────────────────────
echo "# bootstrap: insert executes with touch sandwich"
reset_state

ufw insert 1 allow 22/tcp

assert_mock_called "insert 1 allow 22/tcp" "bootstrap insert: calls real binary with position"
assert_touch_count 2 "bootstrap insert: touch sandwich called"

# ── Bootstrap: route ────────────────────────────────────────────────
echo "# bootstrap: route executes with touch sandwich"
reset_state

ufw route allow in on eth0 out on eth1

assert_mock_called "route allow in on eth0 out on eth1" "bootstrap route: calls real binary"
assert_touch_count 2 "bootstrap route: touch sandwich called"

# ── Bootstrap: delete ───────────────────────────────────────────────
echo "# bootstrap: delete executes with touch sandwich"
reset_state

ufw delete allow 22/tcp

assert_mock_called "delete allow 22/tcp" "bootstrap delete: calls real binary"
assert_touch_count 2 "bootstrap delete: touch sandwich called"

# ── Bootstrap: status passes through ────────────────────────────────
echo "# bootstrap: status passes through"
reset_state

ufw status verbose

assert_mock_called "status verbose" "bootstrap status: passes through to binary"

# ── Bootstrap: reload passes through ────────────────────────────────
echo "# bootstrap: reload passes through"
reset_state

ufw reload

assert_mock_called "reload" "bootstrap reload: passes through to binary"

# ── Bootstrap: reset executes + snapshots ───────────────────────────
echo "# bootstrap: reset calls binary with --force and snapshots"
reset_state

ufw reset

assert_mock_called "reset --force" "bootstrap reset: calls real binary with --force"
assert_touch_count 2 "bootstrap reset: touch sandwich called"

# ── Bootstrap: delete NUM rejected ──────────────────────────────────
echo "# bootstrap: delete NUM rejected"
reset_state

if ufw delete 3 2>/dev/null; then
    fail "bootstrap delete NUM: should error" "returned 0"
else
    pass "bootstrap delete NUM: returns non-zero"
fi
assert_mock_not_called "delete" "bootstrap delete NUM: binary NOT called"

# ── Default: missing args rejected ──────────────────────────────────
echo "# default: missing args rejected"
reset_state

if ufw default 2>/dev/null; then
    fail "default no args: should error" "returned 0"
else
    pass "default no args: returns non-zero"
fi

# ── Logging: missing args rejected ──────────────────────────────────
echo "# logging: missing args rejected"
reset_state

if ufw logging 2>/dev/null; then
    fail "logging no args: should error" "returned 0"
else
    pass "logging no args: returns non-zero"
fi

# ── Pass-through: unknown commands ──────────────────────────────────
echo "# pass-through: unknown commands"
reset_state

ufw version
assert_mock_called "version" "pass-through: version forwarded to binary"

ufw app list
assert_mock_called "app list" "pass-through: app forwarded to binary"

# ── Container: allow records to rules.list ──────────────────────────
echo "# container: allow records to rules.list, no binary"
reset_state
IS_CONTAINER=true

ufw allow 22/tcp

assert_has_line "$RULES" "allow 22/tcp" "container allow: recorded in rules.list"
assert_mock_not_called "allow" "container allow: binary NOT called"

IS_CONTAINER=false

# ── Container: deny records ─────────────────────────────────────────
echo "# container: deny records"
reset_state
IS_CONTAINER=true

ufw deny from 10.0.0.0/8

assert_has_line "$RULES" "deny from 10.0.0.0/8" "container deny: recorded in rules.list"
assert_mock_not_called "deny" "container deny: binary NOT called"

IS_CONTAINER=false

# ── Container: multiple rules ───────────────────────────────────────
echo "# container: multiple rules all recorded"
reset_state
IS_CONTAINER=true

ufw allow 22/tcp
ufw allow 80/tcp
ufw deny from 10.0.0.0/8

assert_line_count "$RULES" 3 "container multi: rules.list has 3 entries"

IS_CONTAINER=false

# ── Container: default records, last-wins per direction ─────────────
echo "# container: default records to defaults.list"
reset_state
IS_CONTAINER=true

ufw default deny incoming

assert_has_line "$DEFAULTS" "deny incoming" "container default: recorded in defaults.list"
assert_mock_not_called "default" "container default: binary NOT called"

IS_CONTAINER=false

# ── Container: default replaces same direction ───────────────────────
echo "# container: default replaces same direction"
reset_state
IS_CONTAINER=true

ufw default deny incoming
ufw default allow incoming

assert_no_line "$DEFAULTS" "deny incoming" "container default replace: old entry removed"
assert_has_line "$DEFAULTS" "allow incoming" "container default replace: new entry present"
assert_line_count "$DEFAULTS" 1 "container default replace: exactly one entry"

IS_CONTAINER=false

# ── Container: default different directions coexist ──────────────────
echo "# container: default different directions coexist"
reset_state
IS_CONTAINER=true

ufw default deny incoming
ufw default allow outgoing

assert_has_line "$DEFAULTS" "deny incoming" "container default multi: incoming present"
assert_has_line "$DEFAULTS" "allow outgoing" "container default multi: outgoing present"
assert_line_count "$DEFAULTS" 2 "container default multi: two entries"

IS_CONTAINER=false

# ── Container: enable records ────────────────────────────────────────
echo "# container: enable records to config.list"
reset_state
IS_CONTAINER=true

ufw enable

assert_has_line "$CONFIG" "enabled" "container enable: recorded in config.list"
assert_mock_not_called "enable" "container enable: binary NOT called"

IS_CONTAINER=false

# ── Container: enable replaces disable ──────────────────────────────
echo "# container: enable replaces disable"
reset_state
IS_CONTAINER=true

ufw disable
ufw enable

assert_no_line "$CONFIG" "disabled" "container enable replaces: disabled removed"
assert_has_line "$CONFIG" "enabled" "container enable replaces: enabled present"

IS_CONTAINER=false

# ── Container: logging records ──────────────────────────────────────
echo "# container: logging records to config.list"
reset_state
IS_CONTAINER=true

ufw logging low

assert_has_line "$CONFIG" "logging low" "container logging: recorded in config.list"
assert_mock_not_called "logging" "container logging: binary NOT called"

IS_CONTAINER=false

# ── Container: logging replaces previous ────────────────────────────
echo "# container: logging replaces previous level"
reset_state
IS_CONTAINER=true

ufw logging low
ufw logging high

assert_no_line "$CONFIG" "logging low" "container logging replace: old removed"
assert_has_line "$CONFIG" "logging high" "container logging replace: new present"

IS_CONTAINER=false

# ── Container: enable + logging coexist ─────────────────────────────
echo "# container: enable and logging coexist"
reset_state
IS_CONTAINER=true

ufw enable
ufw logging low

assert_has_line "$CONFIG" "enabled" "container config coexist: enabled present"
assert_has_line "$CONFIG" "logging low" "container config coexist: logging present"
assert_line_count "$CONFIG" 2 "container config coexist: two entries"

IS_CONTAINER=false

# ── Container: insert records rule without position ──────────────────
echo "# container: insert records rule without position"
reset_state
IS_CONTAINER=true

ufw insert 1 allow 22/tcp

assert_has_line "$RULES" "allow 22/tcp" "container insert: rule recorded without insert prefix"
assert_mock_not_called "insert" "container insert: binary NOT called"

IS_CONTAINER=false

# ── Container: route records ─────────────────────────────────────────
echo "# container: route records"
reset_state
IS_CONTAINER=true

ufw route allow in on eth0 out on eth1

assert_has_line "$RULES" "route allow in on eth0 out on eth1" "container route: recorded with route prefix"
assert_mock_not_called "route" "container route: binary NOT called"

IS_CONTAINER=false

# ── Container: delete removes from rules.list ───────────────────────
echo "# container: delete removes rule from rules.list"
reset_state
IS_CONTAINER=true

ufw allow 22/tcp
ufw allow 80/tcp
ufw delete allow 22/tcp

assert_no_line "$RULES" "allow 22/tcp" "container delete: rule removed from rules.list"
assert_has_line "$RULES" "allow 80/tcp" "container delete: other rules preserved"
assert_mock_not_called "delete" "container delete: binary NOT called"

IS_CONTAINER=false

# ── Container: delete NUM rejected ──────────────────────────────────
echo "# container: delete NUM rejected"
reset_state
IS_CONTAINER=true

if ufw delete 3 2>/dev/null; then
    fail "container delete NUM: should error" "returned 0"
else
    pass "container delete NUM: returns non-zero"
fi
assert_mock_not_called "delete" "container delete NUM: binary NOT called"

IS_CONTAINER=false

# ── Container: status emulates from state ────────────────────────────
echo "# container: status emulates from state"
reset_state
IS_CONTAINER=true

ufw allow 22/tcp
ufw default deny incoming
ufw enable
ufw logging low

output=$(ufw status)

assert_output_contains "$output" "enabled"      "container status: shows enabled"
assert_output_contains "$output" "deny incoming" "container status: shows defaults"
assert_output_contains "$output" "allow 22/tcp"  "container status: shows rules"
assert_output_contains "$output" "logging low"   "container status: shows logging"
assert_mock_not_called "status" "container status: binary NOT called"

IS_CONTAINER=false

# ── Container: status with no state ─────────────────────────────────
echo "# container: status with no state"
reset_state
IS_CONTAINER=true

output=$(ufw status)

assert_output_contains "$output" "No firewall state declared" "container status empty: shows no-state message"

IS_CONTAINER=false

# ── Container: reload is no-op ───────────────────────────────────────
echo "# container: reload is no-op"
reset_state
IS_CONTAINER=true

ufw reload

assert_mock_not_called "reload" "container reload: binary NOT called"

IS_CONTAINER=false

# ── Container: reset clears structured files, no binary ─────────────
echo "# container: reset clears structured files"
reset_state
IS_CONTAINER=true

ufw allow 22/tcp
ufw default deny incoming
ufw enable
ufw logging low
ufw reset

assert_file_missing "$RULES"    "container reset: rules.list cleared"
assert_file_missing "$DEFAULTS" "container reset: defaults.list cleared"
assert_file_missing "$CONFIG"   "container reset: config.list cleared"
assert_mock_not_called "reset"  "container reset: binary NOT called"

IS_CONTAINER=false

# ── ufw_shim_reset: bootstrap is no-op ──────────────────────────────
echo "# ufw_shim_reset: bootstrap is no-op"
reset_state
IS_CONTAINER=false

# Simulate existing structured files (should be untouched)
echo "allow 22/tcp" > "$RULES"
echo "deny incoming" > "$DEFAULTS"
echo "enabled" > "$CONFIG"

ufw_shim_reset

assert_file_exists "$RULES"    "bootstrap shim_reset: files.sh owns cleanup, rules.list untouched"
assert_file_exists "$DEFAULTS" "bootstrap shim_reset: defaults.list untouched"
assert_file_exists "$CONFIG"   "bootstrap shim_reset: config.list untouched"

# ── ufw_shim_reset: container clears structured files ────────────────
echo "# ufw_shim_reset: container clears structured files"
reset_state
IS_CONTAINER=true

ufw allow 22/tcp
ufw default deny incoming
ufw enable
ufw logging low

ufw_shim_reset

assert_file_missing "$RULES"    "container shim_reset: rules.list cleared"
assert_file_missing "$DEFAULTS" "container shim_reset: defaults.list cleared"
assert_file_missing "$CONFIG"   "container shim_reset: config.list cleared"

IS_CONTAINER=false

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "1..${_total}"
echo "# pass: $_pass"
echo "# fail: $_fail"

# Cleanup
/usr/bin/rm -rf "$TEST_DIR"

[[ $_fail -eq 0 ]] && exit 0 || exit 1
