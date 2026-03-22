#!/usr/bin/env bash
## Configure Flatpak
set -oue pipefail

# Arch doesn't include flatpak by default
if [[ "$DISTRO" == "arch" ]]; then
    pacman -Sy --noconfirm --needed flatpak
fi

# Add Flathub remotes (not available by default)
if [[ -f /run/.containerenv ]]; then
    mkdir -p /etc/flatpak/remotes.d
    curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub-beta.flatpakrepo \
        https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo
else
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak remote-add --if-not-exists flathub-beta \
        https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo
fi

# Emulates Flatpak 1.17+ native preinstall: reads INI files from
# /etc/flatpak/preinstall.d/ and installs apps at first boot.
# When native preinstall ships, remove the installation loop below and let
# flatpak's own systemd service handle it. Only the config provisioning
# (copying from /usr/share/system-state.d/flatpak/ to ~/.var/app/) needs to stay.
# https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
mkdir -p /etc/flatpak/preinstall.d
mkdir -p /usr/share/system-state.d/flatpak

FLATPAK_SCRIPT="$POST_DEPLOY_DIR/10-flatpak-apps.sh"
cat > "$FLATPAK_SCRIPT" << 'FLATPAK'
#!/usr/bin/env bash
set -euo pipefail

PREINSTALL_DIR="/etc/flatpak/preinstall.d"
APPS_DIR="/usr/share/system-state.d/flatpak"

# Parse app IDs from preinstall.d INI files and install them.
# This emulates `flatpak preinstall -y` until native support is available.
for ini in "$PREINSTALL_DIR"/*.ini; do
    [[ -f "$ini" ]] || continue

    # Extract app ID from section header: [Flatpak Preinstall <app-id>]
    app_id=$(sed -n 's/^\[Flatpak Preinstall \(.*\)\]$/\1/p' "$ini")
    [[ -n "$app_id" ]] || continue

    # Remote is stored by the build-time shim (native format has no remote field)
    remote="flathub"
    if [[ -f "${APPS_DIR}/${app_id}/.remote" ]]; then
        remote=$(cat "${APPS_DIR}/${app_id}/.remote")
        [[ -n "$remote" ]] || remote="flathub"
    fi

    if ! flatpak install --user --noninteractive "$remote" "$app_id"; then
        echo "WARNING: Failed to install $app_id from $remote" >&2
        continue
    fi

    # Provision default config files into the app's data directory
    app_dir="${APPS_DIR}/${app_id}"
    if [[ -d "$app_dir" ]]; then
        # Copy everything except the .remote marker
        find "$app_dir" -mindepth 1 -not -path "${app_dir}/.remote" -print0 2>/dev/null | while IFS= read -r -d '' src; do
            rel="${src#"$app_dir"/}"
            dest="$HOME/.var/app/$app_id/$rel"
            if [[ -d "$src" ]]; then
                mkdir -p "$dest"
            elif [[ ! -e "$dest" ]]; then
                mkdir -p "$(dirname "$dest")"
                cp "$src" "$dest"
            fi
        done
    fi
done
FLATPAK
chmod +x "$FLATPAK_SCRIPT"
