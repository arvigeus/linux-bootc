# AppImage (appiget)

Minimal AppImage manager for installing, updating, and removing AppImages from GitHub releases or direct URLs.

## Architecture

**appiget** is a standalone CLI tool with no build-system knowledge. It manages state in `/etc/appiget/state.d/` and works on any Linux system.

**The shim** (`provision/shims/appiget.sh`) is a thin wrapper that:

- Enforces `--noninteractive` for safety during builds
- Passes all arguments to appiget
- Records metadata to `/usr/share/system-state.d/appimage/` on baremetal only (for reconciliation)
- Skips recording in containers (clean images need no reconciliation)

**Reconciliation** queries appiget to detect drift and sync state like any other package manager.

## Usage

### During build

Modules call the shim with `--noninteractive`:

```bash
appiget install https://github.com/pingdotgg/t3code --noninteractive
appiget install AppImageCommunity/AppImageUpdate --pattern appimageupdatetool-x86_64.AppImage --name appimageupdatetool --noninteractive
```

The shim validates `--noninteractive` is present, then calls the real appiget.

### At runtime

Users call appiget directly (shim not involved):

```bash
# List installed apps
appiget list

# Update all apps
appiget update

# Update specific app
appiget update t3code

# Remove app
appiget remove t3code --noninteractive
```

### Direct execution

AppImages are installed to `/usr/local/bin/<app-id>`:

```bash
t3code --help
appimageupdatetool --help
```

## Installation sources

**GitHub repo** (queries latest release):
```bash
appiget install https://github.com/AppImageCommunity/AppImageUpdate --pattern appimageupdatetool-x86_64.AppImage
appiget install AppImageCommunity/AppImageUpdate --pattern appimageupdatetool-x86_64.AppImage  # shorthand
```

**Direct URL** (downloads directly):
```bash
appiget install https://github.com/AppImageCommunity/AppImageUpdate/releases/download/v2.1.0/appimageupdatetool-x86_64.AppImage
```

## State tracking

**appiget state** (`/etc/appiget/state.d/`):

- JSON files per app: `t3code.json`, `appimageupdatetool.json`
- Tracks: `repo`, `pattern`, `version`
- Used by: appiget update/remove commands

**Reconciliation state** (`/usr/share/system-state.d/appimage/`):

- INI files per app: `t3code.ini`, `appimageupdatetool.ini`
- Tracks: `repo` (URL or owner/repo)
- Used by: reconciliation to compare desired vs. installed

## Updates

Two-tier strategy:

1. **Delta updates** (if `appimageupdatetool` available)
   - Uses embedded AppImage metadata
   - Fast, low bandwidth

2. **GitHub fallback**
   - Queries GitHub API for latest release
   - Full re-download if newer version available

Auto-updates trigger after package transactions via hooks:

- **Fedora**: `/etc/dnf/libdnf5-plugins/actions.d/appimage-update.actions`
- **Arch**: `/etc/pacman.d/hooks/appimage-update.hook`

## Reconciliation

Detects and fixes drift during `just reconcile`:

**Pre-reconciliation:**

- Seeds `appimage.base.list` from currently installed apps (first run only)

**Post-reconciliation:**

- Compares `/usr/share/system-state.d/appimage/` (declared) with `appiget list` (installed)
- Installs missing apps
- Removes extra apps
- Promotes newly installed to managed list
- Cleans stale baseline entries

## Directory structure

```txt
/usr/local/bin/
  t3code                    # executable AppImage
  appimageupdatetool        # executable AppImage

/etc/appiget/state.d/
  t3code.json               # appiget state
  appimageupdatetool.json   # appiget state

/usr/share/applications/
  t3code.desktop            # desktop entry

/usr/share/icons/hicolor/
  256x256/apps/t3code.png   # icon
```

## Implementation files

- [appiget](../appiget) — main CLI tool
- [provision/files/usr/local/bin/appiget](../provision/files/usr/local/bin/appiget) — installed to system
- [provision/shims/appiget.sh](../provision/shims/appiget.sh) — build-time shim
- [provision/modules/base/appimage.sh](../provision/modules/base/appimage.sh) — installs FUSE + appiget + appimageupdatetool
- [scripts/reconciliation/packages/appimage.sh](../scripts/reconciliation/packages/appimage.sh) — reconciliation
