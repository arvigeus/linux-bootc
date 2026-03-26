#!/usr/bin/env bash
## File reconciliation — backup/expected-based pre/post modes
##
## State dir layout (populated by fs.sh shim during build):
##   expected/<path>  — the file as the build expects it to be
##   backup/<path>    — the file before any build modification
##
## Three possible states per file:
##   backup + expected  →  file was modified by build
##   expected only      →  file was created by build (didn't exist before)
##   backup only        →  file was deleted by build (rm)
##
## Pre-reconciliation:  restore originals so build.sh can re-apply from scratch
## Post-reconciliation: verify build results, flag drift

FILES_STATE_DIR="/usr/share/system-state.d/files"
_FS_BACKUP_DIR="${FILES_STATE_DIR}/backup"
_FS_EXPECTED_DIR="${FILES_STATE_DIR}/expected"

# Helper: collect backup and expected maps from state dir.
# Sets caller's backup_map and expected_map associative arrays.
_reconcile_collect_maps() {
    if [[ -d "$_FS_BACKUP_DIR" ]]; then
        while IFS= read -r -d '' entry; do
            local real_path="${entry#"$_FS_BACKUP_DIR"}"
            backup_map["$real_path"]="$entry"
        done < <(/usr/bin/find "$_FS_BACKUP_DIR" \( -type f -o -type l \) -print0 2>/dev/null)
    fi

    if [[ -d "$_FS_EXPECTED_DIR" ]]; then
        while IFS= read -r -d '' entry; do
            local real_path="${entry#"$_FS_EXPECTED_DIR"}"
            expected_map["$real_path"]="$entry"
        done < <(/usr/bin/find "$_FS_EXPECTED_DIR" \( -type f -o -type l \) -print0 2>/dev/null)
    fi
}

# ── Pre-reconciliation ─────────────────────────────────────────────
#
# Two phases, ordered so Quit is always safe:
#
# Phase 1 — Created-file drift (expected only, no backup)
#   These files will be overwritten by the build regardless.
#   No merge is possible. Options: Ignore / Quit.
#   Nothing is modified during this phase — Quit leaves the
#   filesystem exactly as it was.
#
# Phase 2 — Modified-file drift (backup + expected)
#   The build modifies an existing file. Merge IS meaningful
#   because the user's changes can be folded into the original,
#   and the build re-applies its modifications on top.
#   Options: Accept / Discard / Merge.
#
# After both phases: delete created files, restore originals,
# clear state dir.

reconcile_files_pre() {
    [[ -d "$FILES_STATE_DIR" ]] || return 0

    local -A backup_map=()
    local -A expected_map=()
    _reconcile_collect_maps

    [[ ${#backup_map[@]} -gt 0 || ${#expected_map[@]} -gt 0 ]] || return 0

    echo "=== File Reconciliation (pre) ==="
    local has_drift=false

    # ── Phase 1: Created-file drift (safe to abort) ────────────────
    #
    # Check BEFORE modifying anything. The build will overwrite these
    # files from scratch, so merge is pointless — the only meaningful
    # action is to stop and update the build script first.
    for real_path in "${!expected_map[@]}"; do
        [[ -n "${backup_map[$real_path]+x}" ]] && continue   # has backup → phase 2

        [[ -e "$real_path" ]] || continue
        local expected_file="${expected_map[$real_path]}"
        diff -q "$expected_file" "$real_path" &>/dev/null && continue

        has_drift=true
        echo ""
        echo "--- $real_path (build-created file was modified) ---"
        diff -u "$expected_file" "$real_path" \
            --label "build state: $real_path" \
            --label "current: $real_path" || true
        echo ""
        echo "  This file is created by the build from scratch."
        echo "  Your changes will be overwritten on next run."
        echo "  [i] Ignore (proceed, changes will be lost)"
        echo "  [q] Quit (abort so you can update the build script)"
        read -rp "Choice [i/q]: " choice
        case "$choice" in
            [Qq])
                echo "  Aborted. No files were modified."
                return 1
                ;;
            *)
                echo "  Noted — will be overwritten by build."
                ;;
        esac
    done

    # ── Phase 2: Modified-file drift (backup + expected) ────────────
    #
    # These files existed before the build and were modified by it.
    # Merge is meaningful: the user's changes can be folded into the
    # original, and the build's modifications re-apply on top.
    for real_path in "${!expected_map[@]}"; do
        [[ -n "${backup_map[$real_path]+x}" ]] || continue   # no backup → phase 1

        local expected_file="${expected_map[$real_path]}"

        if [[ ! -e "$real_path" ]]; then
            has_drift=true
            echo ""
            echo "Expected file missing: $real_path"
            echo "  (build modified this, but it no longer exists)"
            echo "  Will be recreated by next build."
            continue
        fi

        if ! diff -q "$expected_file" "$real_path" &>/dev/null; then
            has_drift=true
            echo ""
            echo "--- $real_path (drifted since last build) ---"
            diff -u "$expected_file" "$real_path" \
                --label "build state: $real_path" \
                --label "current: $real_path" || true
            echo ""
            echo "  [a] Accept current file (build applies on top of your version)"
            echo "  [d] Discard changes (restore original, build re-applies from scratch)"
            echo "  [m] Merge interactively (vimdiff: original vs current)"
            read -rp "Choice [a/d/m]: " choice
            case "$choice" in
                [Aa])
                    local backup_file="${backup_map[$real_path]}"
                    /usr/bin/cp -a "$real_path" "$backup_file"
                    echo "  Original updated with current file."
                    ;;
                [Mm])
                    local backup_file="${backup_map[$real_path]}"
                    vimdiff "$backup_file" "$real_path"
                    read -rp "  Accept merged result in original? [y/N] " merge_ans
                    if [[ "$merge_ans" =~ ^[Yy] ]]; then
                        /usr/bin/cp -a "$real_path" "$backup_file"
                        echo "  Original updated with merged result."
                    else
                        echo "  Kept original as-is."
                    fi
                    ;;
                *)
                    echo "  Will restore original."
                    ;;
            esac
        fi
    done

    # ── Delete build-created files (expected only, no backup) ──────
    for real_path in "${!expected_map[@]}"; do
        [[ -n "${backup_map[$real_path]+x}" ]] && continue
        [[ -e "$real_path" ]] && /usr/bin/rm -f "$real_path"
    done

    # ── Restore originals ──────────────────────────────────────────
    for real_path in "${!backup_map[@]}"; do
        local backup_file="${backup_map[$real_path]}"
        /usr/bin/rm -f "$real_path"
        /usr/bin/mkdir -p "$(dirname "$real_path")"
        /usr/bin/mv "$backup_file" "$real_path"
    done

    # ── Clear state dir ────────────────────────────────────────────
    /usr/bin/rm -rf "$FILES_STATE_DIR"
    /usr/bin/mkdir -p "$_FS_BACKUP_DIR" "$_FS_EXPECTED_DIR"

    if ! $has_drift; then
        echo "Files match declared state."
    fi
    echo "Pre-reconciliation complete — originals restored."
}

# ── Post-reconciliation ────────────────────────────────────────────
#
# 1. Verify final state matches real files
# 2. For created files (final only): warn about likely missing touch
# 3. For modified files (backup + expected): offer overwrite/accept/merge
# 4. Check that deleted files (backup-only) are still absent
# 5. Do NOT delete any state — needed for next pre-reconciliation

reconcile_files_post() {
    [[ -d "$FILES_STATE_DIR" ]] || return 0

    local -A backup_map=()
    local -A expected_map=()
    _reconcile_collect_maps

    [[ ${#backup_map[@]} -gt 0 || ${#expected_map[@]} -gt 0 ]] || return 0

    echo "=== File Reconciliation (post) ==="
    local has_drift=false

    # ── Created files (final only): warn about likely build bug ────
    #
    # If a build-created file doesn't match its recorded final state,
    # something modified it after the shim recorded it — most likely
    # an unshimmed command (echo >>, sed -i, curl -o) without a
    # trailing `touch` to update the recorded state.
    for real_path in "${!expected_map[@]}"; do
        [[ -n "${backup_map[$real_path]+x}" ]] && continue   # has backup → handled below
        local expected_file="${expected_map[$real_path]}"

        if [[ ! -e "$real_path" ]]; then
            has_drift=true
            echo ""
            echo "WARNING: Build-created file missing: $real_path"
            echo "  [c] Create from declared state"
            echo "  [i] Ignore"
            read -rp "Choice [c/i]: " ans
            case "$ans" in
                [Cc])
                    /usr/bin/mkdir -p "$(dirname "$real_path")"
                    /usr/bin/cp -a "$expected_file" "$real_path"
                    echo "  Created $real_path"
                    ;;
                *)
                    echo "  Ignored."
                    ;;
            esac
            continue
        fi

        if ! diff -q "$expected_file" "$real_path" &>/dev/null; then
            has_drift=true
            echo ""
            echo "WARNING: $real_path"
            echo "  Build-created file doesn't match recorded state."
            echo "  Likely cause: a shell redirect or unshimmed command modified"
            echo "  the file without a trailing \`touch $real_path\` to record it."
            diff -u "$expected_file" "$real_path" \
                --label "recorded: $real_path" \
                --label "actual: $real_path" || true
            echo ""
            echo "  [a] Accept actual file (update recorded state)"
            echo "  [i] Ignore (state will be stale)"
            read -rp "Choice [a/i]: " choice
            case "$choice" in
                [Aa])
                    /usr/bin/cp -a "$real_path" "$expected_file"
                    echo "  State updated. Consider adding \`touch $real_path\` to your build script."
                    ;;
                *)
                    echo "  Ignored."
                    ;;
            esac
        fi
    done

    # ── Modified files (backup + expected): full drift handling ────
    for real_path in "${!expected_map[@]}"; do
        [[ -n "${backup_map[$real_path]+x}" ]] || continue   # no backup → handled above
        local expected_file="${expected_map[$real_path]}"

        if [[ ! -e "$real_path" ]]; then
            has_drift=true
            echo ""
            echo "Expected file missing: $real_path"
            echo "  [c] Create from declared state"
            echo "  [i] Ignore"
            read -rp "Choice [c/i]: " ans
            case "$ans" in
                [Cc])
                    /usr/bin/mkdir -p "$(dirname "$real_path")"
                    /usr/bin/cp -a "$expected_file" "$real_path"
                    echo "  Created $real_path"
                    ;;
                *)
                    echo "  Ignored."
                    ;;
            esac
            continue
        fi

        if ! diff -q "$expected_file" "$real_path" &>/dev/null; then
            has_drift=true
            echo ""
            echo "--- $real_path ---"
            diff -u "$expected_file" "$real_path" \
                --label "declared: $real_path" \
                --label "current: $real_path" || true
            echo ""
            echo "  [o] Overwrite real file with declared state"
            echo "  [a] Accept current file as new state"
            echo "  [m] Merge interactively (vimdiff)"
            echo "  [i] Ignore"
            read -rp "Choice [o/a/m/i]: " choice
            case "$choice" in
                [Oo])
                    /usr/bin/cp -a "$expected_file" "$real_path"
                    echo "  Overwritten."
                    ;;
                [Aa])
                    /usr/bin/cp -a "$real_path" "$expected_file"
                    echo "  State updated to match current file."
                    ;;
                [Mm])
                    vimdiff "$expected_file" "$real_path"
                    read -rp "  Accept merged result? [y/N] " merge_ans
                    if [[ "$merge_ans" =~ ^[Yy] ]]; then
                        /usr/bin/cp -a "$real_path" "$expected_file"
                        echo "  Accepted. State updated."
                    else
                        echo "  Skipped."
                    fi
                    ;;
                *)
                    echo "  Ignored."
                    ;;
            esac
        fi
    done

    # ── Check deleted files (backup only, no expected) ─────────────
    for real_path in "${!backup_map[@]}"; do
        [[ -n "${expected_map[$real_path]+x}" ]] && continue   # has expected, not a deletion
        if [[ -e "$real_path" ]]; then
            has_drift=true
            echo ""
            echo "Deleted file unexpectedly exists: $real_path"
            echo "  (build deleted this file, but it has reappeared)"
            echo "  [r] Re-delete the file"
            echo "  [k] Keep the file (remove backup state)"
            echo "  [i] Ignore"
            read -rp "Choice: " ans
            case "$ans" in
                [Rr])
                    /usr/bin/rm -f "$real_path"
                    echo "  Re-deleted."
                    ;;
                [Kk])
                    /usr/bin/rm -f "${backup_map[$real_path]}"
                    echo "  Kept file, removed backup state."
                    ;;
                *)
                    echo "  Ignored."
                    ;;
            esac
        fi
    done

    if ! $has_drift; then
        echo "Files match declared state."
    fi
}
