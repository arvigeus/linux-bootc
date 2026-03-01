#!/usr/bin/env bash
## AppImage support (requires FUSE)
set -oue pipefail

dnf install -y fuse-libs
