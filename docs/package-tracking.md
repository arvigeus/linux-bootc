# Package Tracking

Tracks which packages your build scripts install or remove.

## How it works

When a module runs `dnf install -y firefox` or `pacman -S --noconfirm --needed firefox`, the shim:

1. Validates the command (correct flags, etc.)
2. Runs the real package manager
3. Records `firefox` in a managed package list

This creates a clear separation:

- **Managed packages** — declared by your build scripts, recorded in `<manager>.list`
- **Baseline packages** — everything else already on the system, recorded in `<manager>.base.list`

## State directory layout

```
/usr/share/system-state.d/packages/
  dnf.list          — packages installed via dnf in build scripts
  dnf.base.list     — pre-existing packages (seeded on first run)
  pacman.list       — packages installed via pacman
  pacman.base.list  — pre-existing packages
  paru.list         — AUR packages installed via paru
  repos.list        — repository operations (COPRs, PPAs, etc.)
```

## Reconciliation

**Before the build** (pre-reconciliation):

- On first run, seeds the baseline list from currently installed packages
- This tells the system "these packages were here before I started managing things"

**After the build** (post-reconciliation):

- Packages removed from build scripts are flagged (with option to uninstall)
- Manually installed packages not in any list are flagged (with option to add to baseline or remove)
- Baseline is updated as packages move between managed and unmanaged

## Related files

- [provision/shims/package-manager.sh](../provision/shims/package-manager.sh) — shared package tracking logic
- [provision/shims/dnf.sh](../provision/shims/dnf.sh) — dnf shim
- [provision/shims/pacman.sh](../provision/shims/pacman.sh) — pacman shim
- [provision/shims/paru.sh](../provision/shims/paru.sh) — paru shim
- [scripts/reconciliation/packages/dnf.sh](../scripts/reconciliation/packages/dnf.sh) — dnf reconciliation
- [scripts/reconciliation/packages/pacman.sh](../scripts/reconciliation/packages/pacman.sh) — pacman reconciliation
