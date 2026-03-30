# Systemd Service Tracking

Tracks which systemd units your build scripts enable or mask. Only `enabled` and `masked` states are recorded — `disable` and `unmask` remove entries (like `dnf remove` — if you want a service to stay off, mask it).

## How it works

When a module runs `systemctl enable <service>`, the shim:

1. Parses the command to identify subcommand, scope, flags, and unit names
2. Runs the real `systemctl` (or defers to post-deploy)
3. Records the declared state for reconciliation

| Subcommand                                                      | Container                               | Bootstrap               |
| --------------------------------------------------------------- | --------------------------------------- | ----------------------- |
| `enable`, `disable`, `mask`, `unmask`                           | Execute (file ops). Strip `--now`.      | Execute + record state. |
| `start`                                                         | Skip silently (service starts on boot). | Execute, no recording.  |
| `stop`, `restart`, `reload`, `try-restart`, `reload-or-restart` | **Hard error**                          | **Hard error**          |
| `daemon-reload`, `daemon-reexec`                                | Skip silently (no daemon).              | Execute, no recording.  |
| Everything else                                                 | Pass through                            | Pass through            |

`stop`/`restart`/`reload` are non-declarative runtime operations that cannot produce equivalent end state across both modes. Use `enable` for persistent state.

`systemctl enable --now` is equivalent to `enable` + `start`. In containers, `enable` works (symlinks) but `start` doesn't (no init). The shim strips `--now` and runs only `enable`. In bootstrap, `--now` passes through unchanged.

## Scope handling

| Scope                | Container                             | Bootstrap        |
| -------------------- | ------------------------------------- | ---------------- |
| `--system` (default) | Execute directly (file ops)           | Execute + record |
| `--global`           | Execute directly (file ops)           | Execute + record |
| `--user`             | Record only — deferred to post-deploy | Execute + record |

`--system` and `--global` operations are pure file manipulation (creating/removing symlinks) and work in containers. `--user` requires a running user manager, which isn't available during container builds, so these are deferred to post-deploy.

## State directory layout

```
/usr/share/system-state.d/systemd/
  services.list      — managed units (owned by build-time shim)
  services.base.list — baseline units (known but unmanaged)
```

Each line is tab-separated: `unit<TAB>state<TAB>scope`

```
foo.service	enabled	system
bar.service	masked	user
```

## Post-deploy

`provision/deploy/40-systemd.sh` runs on first boot (container only):

1. Reads `services.list`, filters for `user`-scope entries
2. Applies each with `systemctl --user enable` or `systemctl --user mask`

This bridges the gap for `--user` operations that need a running user manager.

## Reconciliation

Same model as packages — managed list vs baseline, but with two states (`enabled` and `masked`) instead of binary present/absent.

**Before the build** (pre-reconciliation):

- Seeds baseline from `systemctl list-unit-files`, filtered to enabled/masked
- Units in states like `static`, `indirect`, `generated` are excluded (system-managed)

**After the build** (post-reconciliation):

- Managed units promoted out of baseline
- Stale baseline entries cleaned (state changed outside build)
- Drifted managed units flagged (actual state ≠ declared state)
- Untracked enabled/masked units flagged (with option to add to baseline)

## Related files

- [provision/shims/systemd.sh](../provision/shims/systemd.sh) — the shim
- [provision/deploy/40-systemd.sh](../provision/deploy/40-systemd.sh) — post-deploy for `--user` services
- [scripts/reconciliation/systemd.sh](../scripts/reconciliation/systemd.sh) — reconciliation
- [tests/test-systemd-shim.sh](../tests/test-systemd-shim.sh) — shim tests
