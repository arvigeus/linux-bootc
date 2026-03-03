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

# Declarative flatpak apps: directory name = app ID, contents = settings for ~/.var/app/
# Other modules drop directories into /usr/share/flatpak-apps.d/<app-id>/
#
# NOTE: Flatpak 1.17+ has native preinstall support via /etc/flatpak/preinstall.d/
# which handles installation only. This custom approach adds default settings provisioning
# (copying directory contents to ~/.var/app/) which the native mechanism doesn't support.
# If settings provisioning is not needed, prefer the native preinstall mechanism.
# https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
mkdir -p /usr/share/flatpak-apps.d

cat > /usr/libexec/post-deploy.d/20-flatpak-apps.sh << 'FLATPAK'
#!/usr/bin/env bash
set -euo pipefail

APPS_DIR="/usr/share/flatpak-apps.d"

for app_dir in "$APPS_DIR"/*/; do
    [[ -d "$app_dir" ]] || continue
    app_id=$(basename "$app_dir")

    flatpak install --user --noninteractive flathub "$app_id"

    # Copy settings to user's .var if the directory has content
    if [[ -n "$(ls -A "$app_dir")" ]]; then
        cp -rn "$app_dir"/* "$HOME/.var/app/$app_id/"
    fi
done
FLATPAK
chmod +x /usr/libexec/post-deploy.d/20-flatpak-apps.sh
