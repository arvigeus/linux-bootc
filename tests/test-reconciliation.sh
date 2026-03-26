#!/usr/bin/env bash
## Tests for scripts/reconciliation/files.sh
##
## Sets up state dir scenarios and verifies reconcile_files_pre/post behavior.
## Non-interactive: pipes responses for drift prompts where needed.
##
## Usage:  bash tests/test-reconciliation.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
WORK_DIR="${TEST_DIR}/work"
STATE_DIR="${TEST_DIR}/state"

mkdir -p "$WORK_DIR" "$STATE_DIR/backup" "$STATE_DIR/expected"

# ── Test framework ─────────────────────────────────────────────────

_pass=0 _fail=0 _total=0

pass() { _pass=$(( _pass + 1 )); _total=$(( _total + 1 )); echo "  ok $_total - $1"; }
fail() { _fail=$(( _fail + 1 )); _total=$(( _total + 1 )); echo "  not ok $_total - $1"; echo "    $2"; }

assert_file_exists()  { [[ -e "$1" ]] && pass "$2" || fail "$2" "expected $1 to exist"; }
assert_file_missing() { [[ ! -e "$1" ]] && pass "$2" || fail "$2" "expected $1 to NOT exist"; }
assert_file_content() {
    local file="$1" expected="$2" label="$3"
    if [[ -e "$file" ]] && [[ "$(cat "$file")" == "$expected" ]]; then
        pass "$label"
    else
        fail "$label" "expected content '$expected', got '$(cat "$file" 2>/dev/null || echo "<missing>")'"
    fi
}

# ── Source reconciliation and override paths ───────────────────────

source "${SCRIPT_DIR}/scripts/reconciliation/files.sh"
FILES_STATE_DIR="$STATE_DIR"
_FS_BACKUP_DIR="${STATE_DIR}/backup"
_FS_EXPECTED_DIR="${STATE_DIR}/expected"

# Helper to set up state dir from scratch
reset_all() {
    /usr/bin/rm -rf "${STATE_DIR}/backup" "${STATE_DIR}/expected" "$WORK_DIR"
    /usr/bin/mkdir -p "${STATE_DIR}/backup" "${STATE_DIR}/expected" "$WORK_DIR"
}

# Helper: create a state entry for a modified file (backup + expected)
make_modified() {
    local real_path="$1" orig_content="$2" final_content="$3"
    /usr/bin/mkdir -p "$(dirname "${_FS_BACKUP_DIR}${real_path}")"
    /usr/bin/mkdir -p "$(dirname "${_FS_EXPECTED_DIR}${real_path}")"
    echo "$orig_content" > "${_FS_BACKUP_DIR}${real_path}"
    echo "$final_content" > "${_FS_EXPECTED_DIR}${real_path}"
}

# Helper: create a state entry for a build-created file (final only)
make_created() {
    local real_path="$1" content="$2"
    /usr/bin/mkdir -p "$(dirname "${_FS_EXPECTED_DIR}${real_path}")"
    echo "$content" > "${_FS_EXPECTED_DIR}${real_path}"
}

# Helper: create a state entry for a deleted file (backup only)
make_deleted() {
    local real_path="$1" orig_content="$2"
    /usr/bin/mkdir -p "$(dirname "${_FS_BACKUP_DIR}${real_path}")"
    echo "$orig_content" > "${_FS_BACKUP_DIR}${real_path}"
}

# ═══════════════════════════════════════════════════════════════════
echo "TAP version 13"
echo "# reconciliation tests"
echo ""

# ── PRE: Modified file, no drift ──────────────────────────────────
echo "# pre: modified file, no drift"
reset_all

make_modified "${WORK_DIR}/config.conf" "original" "modified"
echo "modified" > "${WORK_DIR}/config.conf"  # real matches final → no drift

reconcile_files_pre > /dev/null 2>&1

assert_file_content "${WORK_DIR}/config.conf" "original" \
    "pre no-drift: original restored"
assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/config.conf" \
    "pre no-drift: backup cleaned up"
assert_file_missing "${_FS_EXPECTED_DIR}${WORK_DIR}/config.conf" \
    "pre no-drift: expected cleaned up"

# ── PRE: Modified file with drift, discard changes ────────────────
echo "# pre: modified file, drift → discard"
reset_all

make_modified "${WORK_DIR}/drifted.conf" "original" "build-result"
echo "user-edited" > "${WORK_DIR}/drifted.conf"  # drift!

# Pipe 'd' for discard
echo "d" | reconcile_files_pre > /dev/null 2>&1

assert_file_content "${WORK_DIR}/drifted.conf" "original" \
    "pre drift-discard: original restored (user changes discarded)"

# ── PRE: Modified file with drift, accept changes ─────────────────
echo "# pre: modified file, drift → accept"
reset_all

make_modified "${WORK_DIR}/accepted.conf" "original" "build-result"
echo "user-edited" > "${WORK_DIR}/accepted.conf"  # drift!

# Pipe 'a' for accept (updates backup with current file)
echo "a" | reconcile_files_pre > /dev/null 2>&1

# Accept merges current into backup, then backup is restored to real path
assert_file_content "${WORK_DIR}/accepted.conf" "user-edited" \
    "pre drift-accept: user version preserved as new original"

# ── PRE: Build-created file (final only), no drift ────────────────
echo "# pre: created file, no drift"
reset_all

make_created "${WORK_DIR}/new-file.txt" "created by build"
echo "created by build" > "${WORK_DIR}/new-file.txt"

reconcile_files_pre > /dev/null 2>&1

assert_file_missing "${WORK_DIR}/new-file.txt" \
    "pre created no-drift: file deleted (build will recreate)"

# ── PRE: Build-created file, modified by user → ignore ────────────
echo "# pre: created file, user modified → ignore"
reset_all

make_created "${WORK_DIR}/user-mod.txt" "build version"
echo "user changed this" > "${WORK_DIR}/user-mod.txt"

# Pipe 'i' for ignore (proceed — changes will be lost)
echo "i" | reconcile_files_pre > /dev/null 2>&1

assert_file_missing "${WORK_DIR}/user-mod.txt" \
    "pre created drift-ignore: file deleted (build will recreate)"

# ── PRE: Build-created file, modified by user → quit ─────────────
echo "# pre: created file, user modified → quit"
reset_all

make_created "${WORK_DIR}/quit-me.txt" "build version"
echo "user changed this" > "${WORK_DIR}/quit-me.txt"

# Also set up a modified file to verify nothing gets touched
make_modified "${WORK_DIR}/untouched.conf" "backup-content" "expected-content"
echo "expected-content" > "${WORK_DIR}/untouched.conf"

# Pipe 'q' for quit — should abort, return 1, modify nothing
echo "q" | reconcile_files_pre > /dev/null 2>&1 || true

assert_file_content "${WORK_DIR}/quit-me.txt" "user changed this" \
    "pre created drift-quit: user file untouched"
assert_file_content "${WORK_DIR}/untouched.conf" "expected-content" \
    "pre created drift-quit: modified file untouched"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/quit-me.txt" \
    "pre created drift-quit: state dir intact"

# ── PRE: Deleted file (backup only) ───────────────────────────────
echo "# pre: deleted file (backup only)"
reset_all

make_deleted "${WORK_DIR}/was-deleted.txt" "original before rm"
# Real file does NOT exist (build deleted it)

reconcile_files_pre > /dev/null 2>&1

assert_file_content "${WORK_DIR}/was-deleted.txt" "original before rm" \
    "pre deleted: original restored from backup"

# ── PRE: Deleted file that reappeared ──────────────────────────────
echo "# pre: deleted file that reappeared"
reset_all

make_deleted "${WORK_DIR}/reappeared.txt" "original"
echo "someone recreated me" > "${WORK_DIR}/reappeared.txt"

reconcile_files_pre > /dev/null 2>&1

# Pre-reconciliation removes real file then restores from backup
assert_file_content "${WORK_DIR}/reappeared.txt" "original" \
    "pre deleted-reappeared: restored from backup (not the recreated version)"

# ── PRE: State dir is empty after reconciliation ──────────────────
echo "# pre: state dir clean after reconciliation"
reset_all

make_modified "${WORK_DIR}/a.txt" "backup-a" "expected-a"
make_created "${WORK_DIR}/b.txt" "expected-b"
make_deleted "${WORK_DIR}/c.txt" "backup-c"
echo "expected-a" > "${WORK_DIR}/a.txt"
echo "expected-b" > "${WORK_DIR}/b.txt"

reconcile_files_pre > /dev/null 2>&1

# Count remaining files in state dir
local_count=$(/usr/bin/find "$STATE_DIR" -type f 2>/dev/null | wc -l)
if [[ "$local_count" -eq 0 ]]; then
    pass "pre cleanup: state dir is empty"
else
    fail "pre cleanup: state dir is empty" "found $local_count files remaining"
fi

# ── POST: No drift ────────────────────────────────────────────────
echo "# post: no drift"
reset_all

make_modified "${WORK_DIR}/post.conf" "original" "final"
echo "final" > "${WORK_DIR}/post.conf"  # matches

reconcile_files_post > /dev/null 2>&1

# State should be preserved (not deleted)
assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/post.conf" \
    "post no-drift: backup preserved"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/post.conf" \
    "post no-drift: expected preserved"

# ── POST: Drift detected, overwrite ───────────────────────────────
echo "# post: drift → overwrite"
reset_all

make_modified "${WORK_DIR}/post-drift.conf" "original" "expected"
echo "drifted" > "${WORK_DIR}/post-drift.conf"

echo "o" | reconcile_files_post > /dev/null 2>&1

assert_file_content "${WORK_DIR}/post-drift.conf" "expected" \
    "post drift-overwrite: real file matches declared state"

# ── POST: Drift detected, accept ──────────────────────────────────
echo "# post: drift → accept"
reset_all

make_modified "${WORK_DIR}/post-accept.conf" "original" "expected"
echo "drifted" > "${WORK_DIR}/post-accept.conf"

echo "a" | reconcile_files_post > /dev/null 2>&1

assert_file_content "${WORK_DIR}/post-accept.conf" "drifted" \
    "post drift-accept: real file unchanged"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/post-accept.conf" "drifted" \
    "post drift-accept: state updated to match real"

# ── POST: Missing file → create ───────────────────────────────────
echo "# post: missing file → create"
reset_all

make_created "${WORK_DIR}/missing.txt" "should exist"
# Real file does NOT exist

echo "c" | reconcile_files_post > /dev/null 2>&1

assert_file_content "${WORK_DIR}/missing.txt" "should exist" \
    "post missing-create: file created from state"

# ── POST: Created file drift (missing touch) → accept ─────────────
echo "# post: created file drift → accept"
reset_all

make_created "${WORK_DIR}/no-touch.conf" "shimmed version"
echo "shimmed version plus untracked append" > "${WORK_DIR}/no-touch.conf"

echo "a" | reconcile_files_post > /dev/null 2>&1

assert_file_content "${WORK_DIR}/no-touch.conf" "shimmed version plus untracked append" \
    "post created-drift-accept: real file unchanged"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/no-touch.conf" "shimmed version plus untracked append" \
    "post created-drift-accept: state updated to match real"

# ── POST: Created file drift → ignore ─────────────────────────────
echo "# post: created file drift → ignore"
reset_all

make_created "${WORK_DIR}/no-touch2.conf" "shimmed version"
echo "shimmed version plus untracked append" > "${WORK_DIR}/no-touch2.conf"

echo "i" | reconcile_files_post > /dev/null 2>&1

assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/no-touch2.conf" "shimmed version" \
    "post created-drift-ignore: state unchanged (stale)"

# ── POST: Deleted file (backup only), still absent ────────────────
echo "# post: deleted file stays absent"
reset_all

make_deleted "${WORK_DIR}/still-gone.txt" "was here"
# File doesn't exist on disk — correct

reconcile_files_post > /dev/null 2>&1

# backup should be preserved for next pre-reconciliation
assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/still-gone.txt" \
    "post deleted-absent: backup preserved for next cycle"

# ── POST: Deleted file unexpectedly reappeared → re-delete ────────
echo "# post: deleted reappeared → re-delete"
reset_all

make_deleted "${WORK_DIR}/zombie.txt" "original"
echo "I'm back" > "${WORK_DIR}/zombie.txt"  # reappeared!

echo "r" | reconcile_files_post > /dev/null 2>&1

assert_file_missing "${WORK_DIR}/zombie.txt" \
    "post zombie-redelete: file re-deleted"

# ── POST: Deleted file reappeared → keep ──────────────────────────
echo "# post: deleted reappeared → keep"
reset_all

make_deleted "${WORK_DIR}/kept-zombie.txt" "original"
echo "I'm back" > "${WORK_DIR}/kept-zombie.txt"

echo "k" | reconcile_files_post > /dev/null 2>&1

assert_file_content "${WORK_DIR}/kept-zombie.txt" "I'm back" \
    "post zombie-keep: file kept"
assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/kept-zombie.txt" \
    "post zombie-keep: backup removed (no longer tracking deletion)"

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "1..${_total}"
echo "# pass: $_pass"
echo "# fail: $_fail"

# Cleanup
/usr/bin/rm -rf "$TEST_DIR"

[[ $_fail -eq 0 ]] && exit 0 || exit 1
