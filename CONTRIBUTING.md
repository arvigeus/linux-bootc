# Contributing

Start with [README.md](README.md) for an overview of the two modes (container and bootstrap), what modules, shims, deploy scripts, and reconciliation are, and how they connect. The [docs/](docs/) directory has detailed write-ups for each subsystem.

## Design principles

Both container and bootstrap modes must produce the same end state. If a command works in one mode but cannot produce equivalent results in the other, it must not be allowed in either. The `post-deploy` mechanism bridges the gap for operations that need a running system (Flatpak installs, AppImage integration, `--user` services, VS Code extensions).

This principle drives every shim's design: each command is either executed in both modes, deferred to post-deploy, or rejected outright.

## Key patterns

### `IS_CONTAINER`

Every shim branches on this variable. Set by `provision/lib/detect.sh`, sourced at the top of `provision/build.sh`.

```sh
if [[ "$IS_CONTAINER" == true ]]; then
    # record state only — no real command
else
    # run the real command + record state
fi
```

### Shims are bash functions, not scripts

Shims in `provision/shims/` are sourced into the build environment — they define bash functions that shadow real commands. They are never executed directly. A shim for `foo` defines a `foo()` function; modules call `foo` and get the shim transparently.

### `run_unprivileged`

Defined in `provision/lib/sudo.sh`. Use it for any command that must run as the invoking user (VS Code, Flatpak app installs). The build runs under `sudo`; without this, user-space tools write to root's home or fail outright.

```sh
run_unprivileged code --install-extension ms-python.python
run_unprivileged flatpak install --noninteractive --user flathub flatpak install -y flathub org.gimp.GIMP
```

### State directory

All declared state lands in `/usr/share/system-state.d/`. Subdirectories by subsystem:

```text
/usr/share/system-state.d/
  files/        — file tracking (backup/ and expected/); includes ufw config in bootstrap mode
  packages/     — package lists (*.list, *.base.list)
  flatpak/      — per-app config and .remote files
  appimage/     — per-app INI files
  vscode/       — extensions.list, settings.json, config
  systemd/      — service state (services.list, services.base.list)
  ufw/          — firewall state (rules.list, defaults.list, config.list) — container mode only
```

### Reconciliation helpers

`scripts/reconciliation/packages/common.sh` provides the shared cycle used by all package-like reconcilers:

- `seed_base_list` — seeds `*.base.list` on first run (pre)
- `reconcile_post` — promote → clean → diff → prompt (post); callers must define `_remove_extra_packages` and `_install_missing_packages`

## Running tests

```sh
bash tests/test-fs-shim.sh
bash tests/test-systemd-shim.sh
bash tests/test-reconciliation.sh
```

Output is TAP format. A clean run ends with `# fail: 0`. Run tests after touching anything in `provision/shims/` or `scripts/reconciliation/`.

## Keeping docs up to date

When adding or changing behavior, update the relevant docs alongside the code:

- New shim → add or update the corresponding file in [docs/](docs/)
- Changed reconciliation behavior → update the relevant doc
- New deploy script → update [provision/deploy/README.md](provision/deploy/README.md)
- Anything that changes how the two modes behave differently → update [README.md](README.md)

The docs describe *why* things work the way they do, not just *what* they do — keep that context intact when updating.
