#!/usr/bin/env bash
## File reconciliation
##
## State copies live in /usr/share/system-state.d/files/<path>.
## Build-time shims copy files here on first touch and mirror modifications.
## Works with any file format (INI, JSON, YAML, plain text, etc.).
##
## For each file in the state dir:
##   - If real file doesn't exist: offer to create from state copy
##   - If real file differs from state: show diff, offer overwrite/merge/skip
##   - After resolution: copy real file back to state (so they stay in sync)

FILES_STATE_DIR="/usr/share/system-state.d/files"

reconcile_files() {
    [[ -d "$FILES_STATE_DIR" ]] || return 0

    local -a state_files=()
    mapfile -t state_files < <(find "$FILES_STATE_DIR" -type f 2>/dev/null)
    [[ ${#state_files[@]} -gt 0 ]] || return 0

    echo "=== File Reconciliation ==="
    local has_drift=false

    for state_copy in "${state_files[@]}"; do
        local real_file="${state_copy#"$FILES_STATE_DIR"}"

        if [[ ! -f "$real_file" ]]; then
            has_drift=true
            echo ""
            echo "Config file missing: $real_file"
            echo "  [c] Create from declared state"
            echo "  [d] Delete state copy (no longer needed)"
            echo "  [i] Ignore"
            read -rp "Choice: " ans
            case "$ans" in
                [Cc])
                    mkdir -p "$(dirname "$real_file")"
                    cp "$state_copy" "$real_file"
                    echo "  Created $real_file"
                    ;;
                [Dd])
                    rm -f "$state_copy"
                    echo "  Removed state copy."
                    ;;
                *)
                    echo "  Ignored."
                    ;;
            esac
            continue
        fi

        if ! diff -q "$state_copy" "$real_file" &>/dev/null; then
            has_drift=true
            echo ""
            echo "--- $real_file ---"
            diff -u "$state_copy" "$real_file" \
                --label "declared: $real_file" \
                --label "current: $real_file" || true
            echo ""
            echo "  [o] Overwrite real file with declared state"
            echo "  [a] Accept current file as new state"
            echo "  [m] Merge interactively (vimdiff)"
            echo "  [i] Ignore"
            read -rp "Choice: " choice
            case "$choice" in
                [Oo])
                    cp "$state_copy" "$real_file"
                    echo "  Overwritten."
                    ;;
                [Aa])
                    cp "$real_file" "$state_copy"
                    echo "  State updated to match current file."
                    ;;
                [Mm])
                    local tmpfile="${real_file}.state-new"
                    cp "$state_copy" "$tmpfile"
                    vimdiff "$real_file" "$tmpfile"
                    read -rp "  Accept merged result? [y/N] " merge_ans
                    if [[ "$merge_ans" =~ ^[Yy] ]]; then
                        cp "$real_file" "$state_copy"
                        echo "  Accepted. State updated."
                    else
                        echo "  Skipped."
                    fi
                    rm -f "$tmpfile"
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
