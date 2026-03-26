#!/usr/bin/env bash
## Sudo conveniences
## Future: polkit rules, sudoers.d entries, permission management
set -oue pipefail

# "please" — polite alias for sudo
touch /etc/profile.d/please.sh
cat > /etc/profile.d/please.sh << 'EOF'
alias please='sudo'
EOF
touch /etc/profile.d/please.sh
