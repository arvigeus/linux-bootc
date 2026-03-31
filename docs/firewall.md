# Firewall (UFW)

Shadows `/usr/sbin/ufw` to manage firewall rules declaratively across both modes, with different strategies per mode.

## How it works

| Command                                                | Bootstrap                       | Container                              |
| ------------------------------------------------------ | ------------------------------- | -------------------------------------- |
| `allow`, `deny`, `reject`, `delete`, `insert`, `route` | Execute + snapshot config files | Record to `rules.list`                 |
| `default`                                              | Execute + snapshot config files | Record to `defaults.list` (last-wins)  |
| `logging`                                              | Execute + snapshot config files | Record to `config.list` (last-wins)    |
| `enable`, `disable`                                    | Execute + snapshot config files | Record to `config.list` (last-wins)    |
| `reset`                                                | Execute (--force) + snapshot    | Clear all structured state files       |
| `status`                                               | Pass through to real `ufw`      | Emulate from structured state files    |
| `reload`                                               | Pass through to real `ufw`      | No-op                                  |
| `version`, `--help`, `app`, everything else            | Pass through                    | Pass through                           |

Numeric deletes (`ufw delete NUM`) are rejected in all modes — they are position-dependent and non-declarative.

In container mode, `ufw status` cannot call the real binary (no kernel), so the shim reads the structured state files and prints a summary of declared rules, defaults, and enabled state instead.

## Post-deploy

UFW commands cannot execute in containers: `iptables` probing fails (no kernel access), IPv6 detection breaks (no `/proc/sys/net/ipv6`), and `ufw enable` is fatal. During a container build, the shim records declared state to structured files:

- Rule commands → appended to `rules.list`
- `default` → updates `defaults.list` (replaces existing entry for same direction)
- `enable`/`disable`/`logging` → updates `config.list` (replaces existing entry of same type)
- `delete` → removes the matching entry from `rules.list`
- `insert N` → recorded without the positional index (rule stored by line order)

```text
/usr/share/system-state.d/ufw/
  rules.list     — declared rules (ufw command format, one per line)
  defaults.list  — default policies (one per line)
  config.list    — enabled/disabled, logging level
```

`provision/deploy/50-ufw.sh` applies these on first boot in order: defaults → rules → config. Commands are idempotent — re-running is safe if a previous deploy was interrupted.

## Reconciliation

In bootstrap mode, commands execute immediately on the live system. After each state-changing command, the shim snapshots three files via the [file-tracking](file-tracking.md) infrastructure:

```text
/usr/share/system-state.d/files/
  backup/etc/ufw/   — originals before first modification (saved once)
  expected/etc/ufw/ — declared state (updated after each ufw command)
    user.rules
    user6.rules
    ufw.conf
```

Drift detection and reconciliation are handled entirely by `scripts/reconciliation/files.sh` — ufw config files are treated like any other tracked config file.

**Before the build** (pre-reconciliation): if any of the three files have drifted from their recorded expected state, you are shown a diff and prompted to accept, discard, or merge. Files are then restored to their pre-build originals so the build can re-apply from scratch.

**After the build** (post-reconciliation): verifies the live files match the recorded expected state and prompts on any drift.

See [file-tracking](file-tracking.md) for the full reconciliation flow.

## Related files

- [provision/shims/ufw.sh](../provision/shims/ufw.sh) — build-time shim
- [provision/deploy/50-ufw.sh](../provision/deploy/50-ufw.sh) — post-deploy script
- [tests/test-ufw-shim.sh](../tests/test-ufw-shim.sh) — shim tests
