#!/usr/bin/env bash
## Configure Fedora third-party package repositories
set -oue pipefail

# /var is a tmpfs during build — root's home must exist for gpg/rpm
mkdir -p /var/roothome

echo "max_parallel_downloads=10" >>/etc/dnf/dnf.conf

# Enable Copr subcommand
dnf install -y dnf5-plugins

# RPM Fusion (free + nonfree)
# https://rpmfusion.org/
dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm

# Terra
# https://terra.fyralabs.com/
dnf install -y --nogpgcheck \
    --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
    terra-release

# Copr repositories
# https://copr.fedorainfracloud.org/
# coprs=(
#     <user>/<project>  # description
# )
# for copr in "${coprs[@]}"; do
#     dnf copr enable -y "$copr"
# done
