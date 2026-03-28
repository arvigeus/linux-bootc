#!/usr/bin/env bash
## Apply pending firmware updates after deploy
set -euo pipefail

if command -v fwupdmgr &>/dev/null; then
    fwupdmgr update --no-reboot-check || true
fi
