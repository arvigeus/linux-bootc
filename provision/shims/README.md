# Build-time Shims

Shims are lightweight wrappers that sit between your build scripts and the real system commands. When you write `dnf install -y firefox` or `cp config.conf /etc/`, the shim intercepts the call, runs the real command, and silently records what happened. This recording is what makes reconciliation possible — the system knows what the build *intended*, not just what's currently on disk.

Shims are **transparent** — modules use standard shell commands, and everything works the same with or without shims. The only difference is whether state gets recorded for later reconciliation.

In **container builds**, shims execute the real commands but skip state recording (there's nothing to reconcile inside a disposable container).

To **bypass a shim**, use the full path to the real binary: `/usr/bin/cp`, `/usr/bin/rm`, etc.

## File Tracking (`fs.sh`)

Tracks modifications to config files, assets, and other files on disk.

### What gets tracked

The shim overrides these commands: `cp`, `mv`, `rm`, `touch`, `install`, `ln`. Every time one of these runs, the shim does two things:

1. **Backs up the original** — if the file existed before the build touched it, a copy is saved. This only happens once per file — even if the file is modified multiple times, only the very first version is preserved.
2. **Records the final state** — after the command succeeds, the resulting file is copied to the state directory. This gets updated on every operation, so it always reflects the latest version.

### State directory layout

```
/usr/share/system-state.d/files/
  backup/<path>    — the file before any modification (saved once)
  expected/<path>  — the file as the build expects it to be (updated on every operation)
```

Subdirectories are used rather than a `.bak` suffix to avoid collisions with real `.bak` files (vim, crudini, backup tools) and to keep iteration simple — no filtering needed when walking the tree.

After a build, every tracked file falls into one of three categories:

| State dir has | Meaning |
|---------------|---------|
| `backup` + `expected` | File existed before, build modified it |
| `expected` only | File didn't exist before, build created it |
| `backup` only | File existed before, build deleted it |

### How each command is tracked

**`cp source dest`** — only the destination is tracked, never the source. If `dest` already existed, its original content is backed up. The source file is unchanged, so there's nothing to record.

```sh
# dest is a new file — no backup, just expected
cp /project/my.conf /etc/my.conf

# dest already existed — backup/ saves the old /etc/existing.conf, expected/ saves the new version
cp /project/my.conf /etc/existing.conf
```

**`mv source dest`** — both source and destination are tracked. The source is being removed, so its original content is backed up. If the destination already existed, that's backed up too.

```sh
# source.conf is backed up (it's being moved away), dest.conf gets an expected state
mv /etc/source.conf /etc/dest.conf
```

**Move chains** are handled correctly. If you rename a file through multiple steps, only the very first original is preserved:

```sh
mv /etc/a.conf /etc/b.conf    # a.conf saved to backup/
mv /etc/b.conf /etc/c.conf    # b.conf is NOT backed up (it was created by the previous mv)
                                # Result: backup/etc/a.conf + expected/etc/c.conf
```

This means pre-reconciliation can restore `a.conf` to its original location, and the build re-applies both moves.

**`rm file`** — the original is backed up, but no expected state is recorded (the file is gone). This tells reconciliation "this file was intentionally deleted."

```sh
rm /etc/old-config.conf
# Result: backup/etc/old-config.conf (no expected)
# Pre-reconciliation will restore old-config.conf, then the build deletes it again
```

**`rm -rf directory/`** — every file inside the directory is individually backed up before deletion.

**`touch file`** — if the file exists, backs up the original and records the current content as expected state. If the file doesn't exist, creates it (no backup needed) and records the empty file as expected. This is the key command for tracking shell redirects (see below).

**`install -Dm644 source dest`** — tracked like `cp` (destination only). The `-d` flag (directory creation) is detected and skipped — no file tracking for `install -d`.

**`ln -sf target link`** — the link path is tracked. If something already existed at that path, it's backed up.

### Shell redirects (`>`, `>>`)

Shell redirects like `cat > file` or `echo >> file` can't be intercepted — they're shell syntax, not commands. For these, wrap the operation with `touch`:

```sh
touch /etc/example.conf              # 1. back up original + mark as tracked
cat > /etc/example.conf << 'EOF'     # 2. write content (plain shell)
setting=value
EOF
touch /etc/example.conf              # 3. record final state
```

**Both touches are required.** Here's why:

- **First `touch`**: saves the original (if the file exists) and marks the path as "tracked." Without this, the second `touch` would mistakenly back up the *new* content as the original.
- **Second `touch`**: copies whatever content ended up in the file to the expected state directory.

For appends, the pattern is the same:

```sh
touch /etc/mpv/mpv.conf                # back up original on first contact
echo '# auto-generated' >> /etc/mpv/mpv.conf
jq '...' data.json >> /etc/mpv/mpv.conf
touch /etc/mpv/mpv.conf                # record final state after all appends
```

For `sed -i` or `curl -o`:

```sh
# sed -i can't be shimmed — use touch after
sed -i 's/old/new/' /etc/pacman.conf
touch /etc/pacman.conf                 # record final state

# curl downloads can't be shimmed — use touch after
curl -L -o /etc/mpv/scripts/plugin.lua "https://..."
touch /etc/mpv/scripts/plugin.lua      # record final state
```

Note: if another shimmed command (like `crudini`) already touched the file first, the before state is already saved and you only need the final `touch`.

### What is NOT tracked

- `mkdir` — creating directories doesn't need tracking (the files inside them are what matters)
- Files under `/tmp`, `/var/tmp`, `/proc`, `/sys`, `/dev` — excluded automatically (temp files, downloads, etc. don't need reconciliation)

### Reconciliation in detail

#### Pre-reconciliation (before the next build)

The goal is to restore the filesystem to its state *before* the previous build, so the build can re-apply all modifications from scratch. This is what makes the system behave like an immutable distro — every build starts from a clean slate.

Pre-reconciliation runs in two phases, ordered so you can safely abort:

**Phase 1 — Created files** (have `expected` only, no `backup`):

These are files the build created from scratch (via `cp`, `cat >`, etc.). The build will overwrite them entirely on the next run, so merging your changes into them is pointless — they'd just be replaced.

This phase runs *first*, before anything is modified on disk. If the file hasn't changed since the build, it's silently noted for deletion. If it has drifted, you're shown a diff and prompted:
   - **Ignore** — proceed with reconciliation. Your changes will be lost when the build recreates the file.
   - **Quit** — abort immediately. Nothing has been modified — the filesystem is exactly as you left it. This gives you a chance to incorporate your changes into the build script before running again.

If you need to customize a build-created file, modify the build script itself. This is the same behavior as an immutable distro — files the image creates get overwritten on every deployment.

**Phase 2 — Modified files** (have both `backup` and `expected`):

These are files that existed *before* the build and were modified by it (via `crudini`, `sed -i`, etc.). Merging is meaningful here — your changes can be folded into the original, and the build's modifications re-apply on top.

1. Compare the real file on disk against the recorded `expected` state
2. If they match — no drift. Silently restore the original.
3. If they differ — you're shown a diff and prompted:
   - **Accept** — keeps your changes by replacing the `backup` with your current file. When the build re-runs, it will apply its modifications on top of *your* version instead of the old original.
   - **Discard** — throws away your changes and restores the untouched original. The build re-applies its modifications to the original.
   - **Merge** — opens `vimdiff` with the `backup` file and the real file side by side. You edit to combine changes, then confirm. The merged result replaces the `backup`, so the build applies on top of your merged version.

After both phases: created files are deleted, originals are restored, and the state directory is cleared. The build now runs on a clean filesystem.

**Deleted files** (have `backup` only, no `expected`):

The build deleted this file. Pre-reconciliation restores it from the `backup`, so the build can delete it again.

#### Post-reconciliation (after the build)

Verifies the build produced expected results. State is **not** cleared — it's needed for the next pre-reconciliation cycle.

**Created files** (have `expected` only, no `backup`):

If the real file doesn't match the recorded `expected` state, this usually means an unshimmed command (shell redirect, `sed -i`, `curl -o`) modified the file without a trailing `touch` to update the recorded state. You're shown a diff with a warning and prompted:
   - **Accept** — updates the recorded state to match the actual file. Fixes the stale state, but you should still add the missing `touch` to your build script.
   - **Ignore** — leaves the stale state as-is.

**Modified files** (have both `backup` and `expected`):

If the real file doesn't match the recorded `expected` state, something changed it after the build. You're shown a diff and prompted:
   - **Overwrite** — restores the file to the declared state.
   - **Accept** — updates the recorded state to match the current file.
   - **Merge** — opens `vimdiff` to combine changes interactively.
   - **Ignore** — leaves everything as-is.

**Deleted files** (have `backup` only, no `expected`):

Checks that the file is still absent. If it reappeared, you're prompted to re-delete it or keep it (and stop tracking the deletion).

## Package Tracking (`package-manager.sh`, `dnf.sh`, `pacman.sh`, `paru.sh`)

Tracks which packages your build scripts install or remove.

### How it works

When a module runs `dnf install -y firefox` or `pacman -S --noconfirm --needed firefox`, the shim:

1. Validates the command (correct flags, etc.)
2. Runs the real package manager
3. Records `firefox` in a managed package list

This creates a clear separation:

- **Managed packages** — declared by your build scripts, recorded in `<manager>.list`
- **Baseline packages** — everything else already on the system, recorded in `<manager>.base.list`

### State directory layout

```
/usr/share/system-state.d/packages/
  dnf.list          — packages installed via dnf in build scripts
  dnf.base.list     — pre-existing packages (seeded on first run)
  pacman.list       — packages installed via pacman
  pacman.base.list  — pre-existing packages
  paru.list         — AUR packages installed via paru
  repos.list        — repository operations (COPRs, PPAs, etc.)
```

### How reconciliation uses this

**Before the build** (pre-reconciliation):

- On first run, seeds the baseline list from currently installed packages
- This tells the system "these packages were here before I started managing things"

**After the build** (post-reconciliation):

- Packages removed from build scripts are flagged (with option to uninstall)
- Manually installed packages not in any list are flagged (with option to add to baseline or remove)
- Baseline is updated as packages move between managed and unmanaged

### What about Flatpak?

Flatpak has its own shim (`flatpak.sh`) since apps can't be installed at container build time — they need a running user session. The shim records which apps should be installed, and a post-deploy script handles the actual installation on first boot or after bootstrap.
