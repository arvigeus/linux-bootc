# AppImage (GearLever)

Shadows the `gearlever` command (an alias for `flatpak run it.mijorus.gearlever`) to track AppImage integrations.

## How it works

| Subcommand                           | Container        | Baremetal                                      |
| ------------------------------------ | ---------------- | ---------------------------------------------- |
| `gearlever --integrate --yes <file>` | Records INI only | Integrates + records INI + sets up auto-update |
| Everything else                      | No-op            | Passes through to real gearlever               |

The shim accepts extra metadata arguments that are stripped before passing to the real command:

```sh
gearlever --integrate --yes /tmp/App.AppImage \
    --url="https://..." --repo="owner/repo" --pattern="x86_64.AppImage"
```

Modules don't call this directly — they use `appimage_install_github` from `provision/lib/appimage.sh`:

```sh
appimage_install_github "pingdotgg/t3code" "x86_64.AppImage"
```

This downloads the latest release asset, then calls `gearlever --integrate` with the metadata args.

## State format — INI per app

Each managed app gets a single INI file. The managed list is implicit — every `.ini` file in the state directory is a managed app.

```
/usr/share/system-state.d/appimage/
  t3code.ini            — managed app (INI with metadata)
  another-app.ini       — managed app
  appimage.base.list    — unmanaged baseline (app-id names only)
```

```ini
[appimage]
url=https://github.com/.../T3.Code-1.2.3-x86_64.AppImage
repo=pingdotgg/t3code
pattern=x86_64.AppImage
```

The `repo` and `pattern` fields allow the deploy script and reconciliation to **re-resolve the latest download URL** rather than using the potentially stale one baked into the image.

## Post-deploy

`provision/deploy/30-appimage.sh` installs AppImages on first boot:

1. For each `.ini` file, checks if the app is already integrated
2. Re-resolves the latest URL from GitHub if `repo` + `pattern` are set
3. Downloads, integrates via GearLever, and sets up auto-update

## Reconciliation

Same managed/baseline model, with the managed list derived from `.ini` files:

- **Pre**: Seeds `appimage.base.list` from currently integrated AppImages
- **Post**: Promotes, self-cleans, flags missing managed and untracked extra AppImages. Missing apps are re-downloaded using metadata from their `.ini` file.

## Replacing GearLever

If GearLever is replaced with another AppImage manager, only three things need updating:

1. **`provision/shims/gearlever.sh`** — replace with a shim for the new tool
2. **`provision/deploy/30-appimage.sh`** — use the new tool's CLI
3. **`scripts/reconciliation/packages/appimage.sh`** — update `_appimage_list_installed`, `_remove_extra_packages`, and `_install_missing_packages`

The INI state format and reconciliation logic remain unchanged.

## Related files

- [provision/shims/gearlever.sh](../provision/shims/gearlever.sh) — build-time shim
- [provision/lib/appimage.sh](../provision/lib/appimage.sh) — helper library
- [provision/deploy/30-appimage.sh](../provision/deploy/30-appimage.sh) — post-deploy script
- [scripts/reconciliation/packages/appimage.sh](../scripts/reconciliation/packages/appimage.sh) — reconciliation script
