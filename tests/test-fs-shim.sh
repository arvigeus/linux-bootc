#!/usr/bin/env bash
## Tests for provision/shims/fs.sh
##
## Verifies backup/tracking/state-recording logic without modifying source files.
## Overrides FILES_STATE_DIR to a temp directory and _fs_should_track to allow /tmp paths.
##
## Usage:  bash tests/test-fs-shim.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
WORK_DIR="${TEST_DIR}/work"   # simulates real filesystem
STATE_DIR="${TEST_DIR}/state" # overrides FILES_STATE_DIR

mkdir -p "$WORK_DIR" "$STATE_DIR/backup" "$STATE_DIR/expected"

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
assert_file_content() {
	local file="$1" expected="$2" label="$3"
	if [[ -e "$file" ]] && [[ "$(cat "$file")" == "$expected" ]]; then
		pass "$label"
	else
		fail "$label" "expected content '$expected', got '$(cat "$file" 2>/dev/null || echo "<missing>")'"
	fi
}
assert_tracked() {
	local path="$1" label="$2"
	if [[ -n "${_FS_TRACKED[$path]+x}" ]]; then
		pass "$label"
	else
		fail "$label" "expected $path in _FS_TRACKED"
	fi
}
assert_not_tracked() {
	local path="$1" label="$2"
	if [[ -z "${_FS_TRACKED[$path]+x}" ]]; then
		pass "$label"
	else
		fail "$label" "expected $path NOT in _FS_TRACKED"
	fi
}

# ── Source fs.sh and override state paths ──────────────────────────

source "${SCRIPT_DIR}/provision/shims/fs.sh"

# Override state dirs to our temp location
FILES_STATE_DIR="$STATE_DIR"
_FS_BACKUP_DIR="${STATE_DIR}/backup"
_FS_EXPECTED_DIR="${STATE_DIR}/expected"

# Allow /tmp paths (real _fs_should_track blocks them)
_fs_should_track() { return 0; }

# Ensure we're not in a container
IS_CONTAINER=false

# Helper to reset state between test groups
reset_state() {
	_FS_TRACKED=()
	/usr/bin/rm -rf "${STATE_DIR}/backup" "${STATE_DIR}/expected"
	/usr/bin/mkdir -p "${STATE_DIR}/backup" "${STATE_DIR}/expected"
	/usr/bin/rm -rf "$WORK_DIR"
	/usr/bin/mkdir -p "$WORK_DIR"
}

# ═══════════════════════════════════════════════════════════════════
echo "TAP version 13"
echo "# fs.sh shim tests"
echo ""

# ── Test: touch new file (doesn't exist) ──────────────────────────
echo "# touch: new file"
reset_state

touch "${WORK_DIR}/new.txt"

assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/new.txt" \
	"touch new file: no backup (file didn't exist)"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/new.txt" \
	"touch new file: final state recorded"
assert_tracked "${WORK_DIR}/new.txt" \
	"touch new file: path is tracked"

# ── Test: touch existing file ─────────────────────────────────────
echo "# touch: existing file"
reset_state
echo "original content" >"${WORK_DIR}/exist.txt"

touch "${WORK_DIR}/exist.txt"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/exist.txt" \
	"touch existing: backup created"
assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/exist.txt" "original content" \
	"touch existing: backup has original content"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/exist.txt" \
	"touch existing: final state recorded"

# ── Test: cp to new destination ────────────────────────────────────
echo "# cp: new destination"
reset_state
echo "source data" >"${WORK_DIR}/src.txt"

cp "${WORK_DIR}/src.txt" "${WORK_DIR}/dst.txt"

assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/src.txt" \
	"cp new dest: source NOT backed up"
assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/dst.txt" \
	"cp new dest: no backup for new destination"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/dst.txt" \
	"cp new dest: final state recorded"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/dst.txt" "source data" \
	"cp new dest: final has correct content"
assert_not_tracked "${WORK_DIR}/src.txt" \
	"cp new dest: source not tracked"

# ── Test: cp overwriting existing file ─────────────────────────────
echo "# cp: overwrite existing"
reset_state
echo "source" >"${WORK_DIR}/src.txt"
echo "will be overwritten" >"${WORK_DIR}/existing.txt"

cp "${WORK_DIR}/src.txt" "${WORK_DIR}/existing.txt"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/existing.txt" \
	"cp overwrite: backup created for destination"
assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/existing.txt" "will be overwritten" \
	"cp overwrite: backup has pre-overwrite content"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/existing.txt" "source" \
	"cp overwrite: final has new content"

# ── Test: mv source to new destination ─────────────────────────────
echo "# mv: to new destination"
reset_state
echo "move me" >"${WORK_DIR}/src.txt"

mv "${WORK_DIR}/src.txt" "${WORK_DIR}/dst.txt"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/src.txt" \
	"mv new dest: source backed up"
assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/src.txt" "move me" \
	"mv new dest: backup has source content"
assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/dst.txt" \
	"mv new dest: no backup for new destination"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/dst.txt" \
	"mv new dest: final state recorded at destination"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/dst.txt" "move me" \
	"mv new dest: final has moved content"

# ── Test: mv chain (a→b→c) ────────────────────────────────────────
echo "# mv chain: a→b→c"
reset_state
echo "chain data" >"${WORK_DIR}/a.txt"

mv "${WORK_DIR}/a.txt" "${WORK_DIR}/b.txt"
mv "${WORK_DIR}/b.txt" "${WORK_DIR}/c.txt"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/a.txt" \
	"mv chain: only a.txt has backup"
assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/b.txt" \
	"mv chain: b.txt has no backup (was shim-created)"
assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/c.txt" \
	"mv chain: c.txt has no backup"
assert_file_missing "${_FS_EXPECTED_DIR}${WORK_DIR}/b.txt" \
	"mv chain: b.txt final state cleaned up"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/c.txt" \
	"mv chain: c.txt has final state"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/c.txt" "chain data" \
	"mv chain: c.txt final has original content"

# ── Test: mv overwriting existing ──────────────────────────────────
echo "# mv: overwrite existing"
reset_state
echo "source" >"${WORK_DIR}/src.txt"
echo "target original" >"${WORK_DIR}/dst.txt"

mv "${WORK_DIR}/src.txt" "${WORK_DIR}/dst.txt"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/src.txt" \
	"mv overwrite: source backed up"
assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/dst.txt" \
	"mv overwrite: destination backed up"
assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/dst.txt" "target original" \
	"mv overwrite: dest backup has pre-overwrite content"

# ── Test: rm file ──────────────────────────────────────────────────
echo "# rm: single file"
reset_state
echo "delete me" >"${WORK_DIR}/doomed.txt"

rm "${WORK_DIR}/doomed.txt"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/doomed.txt" \
	"rm: backup created"
assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/doomed.txt" "delete me" \
	"rm: backup has original content"
assert_file_missing "${_FS_EXPECTED_DIR}${WORK_DIR}/doomed.txt" \
	"rm: no final state (file is deleted)"
assert_tracked "${WORK_DIR}/doomed.txt" \
	"rm: path still in tracked set"

# ── Test: rm + recreate ────────────────────────────────────────────
echo "# rm + recreate"
reset_state
echo "original" >"${WORK_DIR}/phoenix.txt"

rm "${WORK_DIR}/phoenix.txt"
# Recreate via touch-sandwich
touch "${WORK_DIR}/phoenix.txt"
printf "reborn" >"${WORK_DIR}/phoenix.txt"
touch "${WORK_DIR}/phoenix.txt"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/phoenix.txt" \
	"rm+recreate: backup preserved from before deletion"
assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/phoenix.txt" "original" \
	"rm+recreate: backup has original content"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/phoenix.txt" \
	"rm+recreate: final state from recreate"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/phoenix.txt" "reborn" \
	"rm+recreate: final has new content"

# ── Test: rm -rf directory ─────────────────────────────────────────
echo "# rm -rf: directory"
reset_state
/usr/bin/mkdir -p "${WORK_DIR}/mydir/sub"
echo "file1" >"${WORK_DIR}/mydir/a.txt"
echo "file2" >"${WORK_DIR}/mydir/sub/b.txt"

rm -rf "${WORK_DIR}/mydir"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/mydir/a.txt" \
	"rm -rf dir: a.txt backed up"
assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/mydir/sub/b.txt" \
	"rm -rf dir: sub/b.txt backed up"
assert_file_missing "${_FS_EXPECTED_DIR}${WORK_DIR}/mydir/a.txt" \
	"rm -rf dir: no final for a.txt"

# ── Test: touch-sandwich — write new file ──────────────────────────
echo "# touch-sandwich: write new file"
reset_state

touch "${WORK_DIR}/written.txt"
printf "hello world" >"${WORK_DIR}/written.txt"
touch "${WORK_DIR}/written.txt"

assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/written.txt" \
	"sandwich new: no backup (file didn't exist)"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/written.txt" "hello world" \
	"sandwich new: final has written content"
assert_file_content "${WORK_DIR}/written.txt" "hello world" \
	"sandwich new: real file has content"

# ── Test: touch-sandwich — overwrite existing file ─────────────────
echo "# touch-sandwich: overwrite existing"
reset_state
echo "old" >"${WORK_DIR}/overwrite.txt"

touch "${WORK_DIR}/overwrite.txt"
printf "new" >"${WORK_DIR}/overwrite.txt"
touch "${WORK_DIR}/overwrite.txt"

assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/overwrite.txt" "old" \
	"sandwich overwrite: backup has old content"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/overwrite.txt" "new" \
	"sandwich overwrite: final has new content"

# ── Test: touch-sandwich — heredoc ─────────────────────────────────
echo "# touch-sandwich: heredoc"
reset_state

touch "${WORK_DIR}/heredoc.txt"
cat >"${WORK_DIR}/heredoc.txt" <<'EOF'
line one
line two
EOF
touch "${WORK_DIR}/heredoc.txt"

assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/heredoc.txt" \
	"sandwich heredoc: final state recorded"

# ── Test: touch-sandwich — append ──────────────────────────────────
echo "# touch-sandwich: append"
reset_state
printf "first" >"${WORK_DIR}/append.txt"

touch "${WORK_DIR}/append.txt"
printf " second" >>"${WORK_DIR}/append.txt"
printf " third" >>"${WORK_DIR}/append.txt"
touch "${WORK_DIR}/append.txt"

assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/append.txt" "first" \
	"sandwich append: backup captured before first touch"
assert_file_content "${WORK_DIR}/append.txt" "first second third" \
	"sandwich append: real file has appended content"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/append.txt" "first second third" \
	"sandwich append: final reflects all appends"

# ── Test: install -d (directory only, no tracking) ─────────────────
echo "# install -d: no tracking"
reset_state

install -d "${WORK_DIR}/installed-dir"

assert_file_missing "${_FS_EXPECTED_DIR}${WORK_DIR}/installed-dir" \
	"install -d: no final state for directory"

# ── Test: install -Dm644 ──────────────────────────────────────────
echo "# install -Dm644"
reset_state
echo "binary data" >"${WORK_DIR}/src-bin"

install -Dm644 "${WORK_DIR}/src-bin" "${WORK_DIR}/dest/path/installed"

assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/dest/path/installed" \
	"install -Dm644: no backup (new destination)"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/dest/path/installed" \
	"install -Dm644: final state recorded"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/dest/path/installed" "binary data" \
	"install -Dm644: final has correct content"

# ── Test: ln -sf ───────────────────────────────────────────────────
echo "# ln -sf"
reset_state
echo "target" >"${WORK_DIR}/link-target"

ln -sf "${WORK_DIR}/link-target" "${WORK_DIR}/mylink"

assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/mylink" \
	"ln -sf: no backup (new link)"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/mylink" \
	"ln -sf: final state recorded"
assert_tracked "${WORK_DIR}/mylink" \
	"ln -sf: link path tracked"

# ── Test: ln -sf overwriting existing file ─────────────────────────
echo "# ln -sf: overwrite existing"
reset_state
echo "will be replaced" >"${WORK_DIR}/existing-link"
echo "target" >"${WORK_DIR}/link-target"

ln -sf "${WORK_DIR}/link-target" "${WORK_DIR}/existing-link"

assert_file_exists "${_FS_BACKUP_DIR}${WORK_DIR}/existing-link" \
	"ln -sf overwrite: backup created for existing file"
assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/existing-link" "will be replaced" \
	"ln -sf overwrite: backup has pre-link content"

# ── Test: container mode skips state recording ─────────────────────
echo "# container mode: no state"
reset_state
IS_CONTAINER=true # pretend we're in a container

echo "container test" >"${WORK_DIR}/container.txt"
touch "${WORK_DIR}/container.txt"

assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/container.txt" \
	"container: no backup recorded"
assert_file_missing "${_FS_EXPECTED_DIR}${WORK_DIR}/container.txt" \
	"container: no final recorded"

# Restore non-container mode
IS_CONTAINER=false

# ── Test: fs_shim_reset clears everything ──────────────────────────
echo "# fs_shim_reset"
reset_state
echo "tracked" >"${WORK_DIR}/tracked.txt"
touch "${WORK_DIR}/tracked.txt"

fs_shim_reset

assert_not_tracked "${WORK_DIR}/tracked.txt" \
	"reset: tracked set cleared"
assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/tracked.txt" \
	"reset: backup dir cleaned"
assert_file_missing "${_FS_EXPECTED_DIR}${WORK_DIR}/tracked.txt" \
	"reset: final dir cleaned"
assert_file_exists "$_FS_BACKUP_DIR" \
	"reset: backup dir recreated"
assert_file_exists "$_FS_EXPECTED_DIR" \
	"reset: final dir recreated"

# ── Test: second touch on same file doesn't re-create backup ─────────
echo "# idempotent: second touch preserves backup"
reset_state
echo "first version" >"${WORK_DIR}/idem.txt"

touch "${WORK_DIR}/idem.txt"
# Modify the real file
echo "second version" >"${WORK_DIR}/idem.txt"
touch "${WORK_DIR}/idem.txt"

assert_file_content "${_FS_BACKUP_DIR}${WORK_DIR}/idem.txt" "first version" \
	"idempotent: backup still has first version (not overwritten)"
assert_file_content "${_FS_EXPECTED_DIR}${WORK_DIR}/idem.txt" "second version" \
	"idempotent: final updated to second version"

# ── Test: cp -r directory ──────────────────────────────────────────
echo "# cp -r: directory"
reset_state
/usr/bin/mkdir -p "${WORK_DIR}/srcdir/sub"
echo "f1" >"${WORK_DIR}/srcdir/a.txt"
echo "f2" >"${WORK_DIR}/srcdir/sub/b.txt"

cp -r "${WORK_DIR}/srcdir" "${WORK_DIR}/dstdir"

assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/dstdir/a.txt" \
	"cp -r: final for a.txt"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/dstdir/sub/b.txt" \
	"cp -r: final for sub/b.txt"
assert_file_missing "${_FS_BACKUP_DIR}${WORK_DIR}/dstdir/a.txt" \
	"cp -r: no backup for new files"

# ── Test: multi-source cp ─────────────────────────────────────────
echo "# cp: multi-source to directory"
reset_state
echo "one" >"${WORK_DIR}/m1.txt"
echo "two" >"${WORK_DIR}/m2.txt"
/usr/bin/mkdir -p "${WORK_DIR}/mdir"

cp "${WORK_DIR}/m1.txt" "${WORK_DIR}/m2.txt" "${WORK_DIR}/mdir/"

assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/mdir/m1.txt" \
	"cp multi: final for m1.txt"
assert_file_exists "${_FS_EXPECTED_DIR}${WORK_DIR}/mdir/m2.txt" \
	"cp multi: final for m2.txt"

# ═══════════════════════════════════════════════════════════════════
echo ""
echo "1..${_total}"
echo "# pass: $_pass"
echo "# fail: $_fail"

# Cleanup
/usr/bin/rm -rf "$TEST_DIR"

[[ $_fail -eq 0 ]] && exit 0 || exit 1
