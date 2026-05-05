#!/usr/bin/env bash
set -oue pipefail

# Drop stalled mirrors and retry instead of hanging the build
touch /etc/dnf/dnf.conf
cat >>/etc/dnf/dnf.conf <<-'EOF'
	minrate=100k
	timeout=15
	retries=10
	fastestmirror=True
EOF
