#!/usr/bin/env bash
## AppImage support (requires FUSE)
set -oue pipefail

case "$PACKAGE_MANAGER" in
    dnf)    dnf install -y fuse-libs ;;
    pacman) pacman -Sy --noconfirm --needed fuse2 ;;
esac

flatpak install --noninteractive --user flathub it.mijorus.gearlever

# Convenience command so users can type `gearlever` instead of the full flatpak invocation
touch /etc/profile.d/gearlever.sh
cat > /etc/profile.d/gearlever.sh << 'EOF'
alias gearlever='flatpak run it.mijorus.gearlever'
EOF
touch /etc/profile.d/gearlever.sh
