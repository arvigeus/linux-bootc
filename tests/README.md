# Tests

Tests verify that the build system's internal machinery works correctly — specifically the parts that track what your build scripts do and the reconciliation logic that uses that tracking.

## What the tests cover

### File tracking (`test-fs-shim.sh`)

Tests the file system shim that records file operations during builds. Verifies that:

- **Originals are backed up** — when a build script modifies an existing file, the original version is saved
- **Final state is recorded** — after each operation, the resulting file is captured
- **`cp` only tracks the destination** — copying a file doesn't back up the source (it wasn't changed)
- **`mv` chains work correctly** — `mv a b` then `mv b c` only backs up `a` (the original), not the intermediate `b`
- **`rm` preserves the original** — deleting a file saves it so it can be restored before the next build
- **`rm` + recreate** — if a file is deleted then recreated, the original from before deletion is preserved
- **Directories are handled** — `rm -rf` and `cp -r` track individual files within directories
- **The touch-sandwich pattern works** — `touch` before a write backs up the original; `touch` after records the result
- **Second touches don't overwrite backups** — the original is saved once, even if the file is modified multiple times
- **Container mode skips tracking** — inside containers, commands run but nothing is recorded
- **Reset clears everything** — `fs_shim_reset` wipes all tracked state for a clean build

### Systemd service tracking (`test-systemd-shim.sh`)

Tests the systemd shim that intercepts `systemctl` commands during builds. Verifies that:

- **`enable`/`mask` record state** — declared service state is written to `services.list` with scope
- **`disable`/`unmask` remove entries** — like `dnf remove`, the unit is no longer declared
- **Unit names are normalized** — bare names like `foo` become `foo.service`; suffixed names like `foo.timer` are preserved
- **Multiple units per command work** — `systemctl enable a.service b.timer` records both
- **Re-recording replaces entries** — enabling then masking a unit produces one entry, not two
- **`--now` is stripped in containers** — the enable portion executes, the start portion is dropped
- **`--now` passes through in bootstrap** — the full command runs normally
- **Scope handling** — `--system`, `--global`, `--user` recorded as scope column in single `services.list`
- **`--user` in containers defers to post-deploy** — records state without executing
- **Mixed scopes coexist** — system, global, and user entries in one file
- **Scope-aware disable** — disabling a system-scope unit preserves the same unit in user scope
- **`start` is skipped in containers** — services start on boot anyway
- **`stop`/`restart`/`reload` are hard errors** — non-declarative commands that can't ensure same end state
- **`daemon-reload` is skipped in containers** — no daemon to reload
- **Reset clears managed list but preserves baseline** — `systemd_shim_reset` wipes `services.list` but keeps `services.base.list`
- **Unknown subcommands pass through** — `status`, `is-enabled`, etc. go directly to the real binary

### Reconciliation (`test-reconciliation.sh`)

Tests the logic that runs before and after each build to handle drift. Verifies that:

**Pre-reconciliation** (restoring originals before a build re-runs):

- Modified files are restored to their original state
- Build-created files (that didn't exist before) are deleted
- Deleted files (removed by the build) are restored from backup
- When drift is detected (someone changed a file after the build), the user is prompted to merge, discard, or keep
- The state directory is completely clean after pre-reconciliation

**Post-reconciliation** (verifying the build produced expected results):

- Files that match the expected state pass silently
- Drift is flagged with options to overwrite, accept, or merge
- Deleted files that unexpectedly reappear are flagged
- State is preserved for the next pre-reconciliation cycle

## How to run

```sh
bash tests/test-fs-shim.sh
bash tests/test-systemd-shim.sh
bash tests/test-reconciliation.sh
```

Or run all:

```sh
bash tests/test-fs-shim.sh && bash tests/test-systemd-shim.sh && bash tests/test-reconciliation.sh
```

Tests output [TAP](https://testanything.org/) (Test Anything Protocol) format. A passing run ends with `# fail: 0`.

## How they work

Tests source the real shim and reconciliation scripts, then override a few variables to run in an isolated temp directory:

- `FILES_STATE_DIR` points to a temp directory instead of `/usr/share/system-state.d/files/`
- `_fs_should_track()` is overridden to allow `/tmp` paths (normally excluded)
- `_fs_is_container()` is overridden to simulate container/non-container modes

No source files are modified. The tests use the same code paths as a real build — they just redirect where state gets stored.

For reconciliation tests, the state directory is set up manually (simulating what a build would have produced), then the reconciliation functions are called and the results checked. Interactive prompts are handled by piping responses to stdin.
