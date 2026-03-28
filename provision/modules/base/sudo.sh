#!/usr/bin/env bash
## Sudo conveniences
## Future: polkit rules, sudoers.d entries, permission management
set -oue pipefail

# "please" — polite alias for sudo
bash_alias sudo please sudo
