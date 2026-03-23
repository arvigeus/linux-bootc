#!/usr/bin/env bash
## Post-update runner: executes drop-in scripts once per new image deployment
## Other modules drop executable scripts into /usr/libexec/post-deploy.d/
set -oue pipefail

# Create drop-in directory for post-deploy scripts
POST_DEPLOY_DIR="/usr/libexec/post-deploy.d"
mkdir -p "$POST_DEPLOY_DIR"

if [[ -f /run/.containerenv ]]; then
    # bootc: runner checks image digest, skips if unchanged
    cat > /usr/libexec/post-deploy << 'RUNNER'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/post-deploy"
STATE_FILE="$STATE_DIR/image-id"
SCRIPTS_DIR="/usr/libexec/post-deploy.d"

IMAGE_ID=$(bootc status --json | jq -r '.status.booted.image.imageDigest')
if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "$IMAGE_ID" ]]; then
    exit 0
fi

for script in "$SCRIPTS_DIR"/*.sh; do
    [[ -x "$script" ]] || continue
    echo ":: Running post-deploy: ${script##*/}"
    "$script"
done

mkdir -p "$STATE_DIR"
echo "$IMAGE_ID" > "$STATE_FILE"
RUNNER

    # Systemd user service
    mkdir -p /usr/lib/systemd/user
    cat > /usr/lib/systemd/user/post-deploy.service << 'SERVICE'
[Unit]
Description=Run post-deploy scripts after new image deployment
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/post-deploy
RemainAfterExit=yes

[Install]
WantedBy=default.target
SERVICE
    systemctl --global enable post-deploy.service
else
    # Non-bootc: runner just executes all scripts unconditionally
    cat > /usr/libexec/post-deploy << 'RUNNER'
#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="/usr/libexec/post-deploy.d"

for script in "$SCRIPTS_DIR"/*.sh; do
    [[ -x "$script" ]] || continue
    echo ":: Running post-deploy: ${script##*/}"
    "$script"
done
RUNNER
fi
chmod +x /usr/libexec/post-deploy
