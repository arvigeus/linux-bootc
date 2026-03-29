# Flatpak

Shadows `/usr/bin/flatpak` to handle app installation across both build modes.

## Why a separate shim?

Flatpak needs D-Bus and a running user session to install apps. In container builds, neither is available. The shim records what _should_ be installed and defers the actual installation to a post-deploy script that runs on first boot.

## How it works

| Subcommand           | Container                                             | Baremetal                               |
| -------------------- | ----------------------------------------------------- | --------------------------------------- |
| `flatpak remote-add` | Downloads `.flatpakrepo` to `/etc/flatpak/remotes.d/` | Runs real command + records remote name |
| `flatpak install`    | Writes preinstall INI + records remote                | Installs + writes INI + records state   |
| `flatpak app-config` | Writes config to state dir                            | Same                                    |
| Everything else      | Passes through                                        | Passes through                          |

## State directory layout

```
/usr/share/system-state.d/flatpak/
  <app-id>/
    .remote           — which remote the app came from
    <config-files>    — provisioned config for ~/.var/app/
/etc/flatpak/
  preinstall.d/
    <app-id>.ini      — marks app for installation at boot
  remotes.d/
    <name>.flatpakrepo — remote definition (container only)
```

## Post-deploy

`provision/deploy/20-flatpak.sh` runs on first boot (container only):

1. Reads preinstall INI files
2. Installs apps that aren't already present
3. Copies provisioned config into `~/.var/app/`

## Reconciliation

Same model as system packages — managed list vs baseline:

- **Pre**: Seeds `flatpak.base.list` from currently installed apps
- **Post**: Promotes managed out of baseline, self-cleans stale entries, flags missing managed and untracked extra apps. Also checks that declared remotes are still present.

## Module usage

Modules use standard flatpak syntax — the shim handles the rest:

```sh
flatpak install --noninteractive --user flathub org.example.App
flatpak app-config org.example.App config/settings.json '{"key": "val"}'
```

## Related files

- [provision/shims/flatpak.sh](../provision/shims/flatpak.sh) — build-time shim
- [provision/deploy/20-flatpak.sh](../provision/deploy/20-flatpak.sh) — post-deploy script
- [scripts/reconciliation/flatpak.sh](../scripts/reconciliation/flatpak.sh) — reconciliation script
