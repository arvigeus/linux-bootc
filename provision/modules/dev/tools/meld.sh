#!/usr/bin/env bash
## Meld — visual diff and merge tool
## https://meldmerge.org/
set -oue pipefail

packages=(
	meld
)

case "$PACKAGE_MANAGER" in
dnf)
	dnf install -y "${packages[@]}"
	;;
pacman)
	pacman -S --noconfirm --needed "${packages[@]}"
	;;
esac

# Ensure the user profile reads both the user db and the system db
# we're about to populate. Without this, /etc/dconf/db/local is ignored.
fs_write /etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF

filename_filters=(
	"('Backups', true, '#*# .#* ~* *~ *.{orig,bak,swp}')"
	"('OS-specific metadata', true, '.DS_Store ._* .Spotlight-V100 .Trashes Thumbs.db Desktop.ini')"
	"('Version Control', true, '_MTN .bzr .svn .svn .hg .fslckout _FOSSIL_ .fos CVS _darcs .git .svn .osc')"
	"('Binaries', true, '*.{pyc,a,obj,o,so,la,lib,dll,exe}')"
	"('Media', true, '*.{jpg,gif,png,bmp,wav,mp3,mp4,ogg,flac,avi,mpg,mpeg,xcf,xpm}')"
	"('Node Modules', true, 'node_modules package-lock.json bun.lockb bun.lock pnpm-lock.yaml yarn.lock')"
)
# System-wide defaults compiled by `dconf update` into /etc/dconf/db/local.
# Users can still override individual keys; this is the baseline.
fs_write /etc/dconf/db/local.d/00-meld <<EOF
[org/gnome/meld]
filename-filters=[$(printf ',%s' "${filename_filters[@]}" | cut -c2-)]
highlight-current-line=true
indent-width=4
show-line-numbers=true
style-scheme='classic'
wrap-mode='none'
EOF

dconf update

bash_env meld DIFFPROG meld
