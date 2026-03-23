#!/usr/bin/env bash
## Configure Arch third-party package repositories
set -oue pipefail

# --- Pacman configuration ---
crudini --set /etc/pacman.conf options VerbosePkgLists ""
crudini --set /etc/pacman.conf options ParallelDownloads 10

# --- Chaotic-AUR ---
# Pre-built AUR packages: https://aur.chaotic.cx/
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
crudini --set /etc/pacman.conf chaotic-aur Include /etc/pacman.d/chaotic-mirrorlist

# --- AUR helper ---
pacman -Sy --noconfirm --needed chaotic-aur/paru

# --- Enable multilib (32-bit support: Wine, Steam, etc.) ---
crudini --set /etc/pacman.conf multilib Include /etc/pacman.d/mirrorlist

# --- ALHP.GO ---
# Packages compiled for your CPU microarchitecture: https://somegit.dev/ALHP/ALHP.GO
# Set CPU_OPTIMIZATION_LEVEL to v2, v3, or v4 (check: /lib/ld-linux-x86-64.so.2 --help)
if [[ -n "${CPU_OPTIMIZATION_LEVEL:-}" ]]; then
    paru -Sy --noconfirm --needed alhp-keyring alhp-mirrorlist

    # ALHP repos must appear before their standard counterparts for priority.
    # Uses sed because crudini appends sections at the end (wrong order).
    # Guard against re-runs on baremetal: only insert if not already present.
    for repo in core extra multilib; do
        if ! crudini --get /etc/pacman.conf "${repo}-x86-64-${CPU_OPTIMIZATION_LEVEL}" &>/dev/null; then
            sed -i "/^\[${repo}\]/i [${repo}-x86-64-${CPU_OPTIMIZATION_LEVEL}]\nInclude = /etc/pacman.d/alhp-mirrorlist\n" /etc/pacman.conf
        fi
    done

    # Mirror state for baremetal reconciliation (crudini can't control section order)
    if [[ ! -f /run/.containerenv ]]; then
        mkdir -p "${FILES_STATE_DIR}/etc"
        cp /etc/pacman.conf "${FILES_STATE_DIR}/etc/pacman.conf"
    fi
fi

# --- Rollback: pin official repos to a specific date ---
# Only affects official repos (core, extra, multilib). Chaotic-AUR and ALHP are unaffected.
# ROLLBACK_DATE="2025/02/25"  # specific date
# for repo in core extra multilib; do
#     crudini --set /etc/pacman.conf "$repo" Server "https://archive.archlinux.org/repos/${ROLLBACK_DATE}/\$repo/os/\$arch"
# done

# --- Baremetal installs only ---
if [[ ! -f /run/.containerenv ]]; then
    pacman -S --noconfirm --needed arch-update pacman-contrib reflector

    # Mirror ranking: keep mirrorlist sorted by speed
    mkdir -p /etc/xdg/reflector
    cat > /etc/xdg/reflector/reflector.conf <<'REFLECTOR'
--latest 50
--protocol https
--sort rate
--age 24
--save /etc/pacman.d/mirrorlist
REFLECTOR

    # Pacman hooks
    mkdir -p /etc/pacman.d/hooks

    # Re-rank mirrors when pacman-mirrorlist is upgraded
    cat > /etc/pacman.d/hooks/reflector-update.hook <<'HOOK'
[Trigger]
Operation = Upgrade
Type = Package
Target = pacman-mirrorlist

[Action]
Description = Updating mirrorlist with reflector...
When = PostTransaction
Depends = reflector
Exec = /usr/bin/systemctl start reflector.service
HOOK

    # Periodic mirror re-ranking (weekly by default)
    systemctl enable reflector.timer

fi
