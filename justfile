set dotenv-load

default: build run

DISTRO := env("DISTRO", "fedora")

IMAGE_NAME := env("IMAGE_NAME", "linux-bootc")
IMAGE_TAG := env("IMAGE_TAG", "latest")

# Build the bootc container image
build:
    podman build -f Containerfile.{{DISTRO}} \
        -t {{IMAGE_NAME}}:{{IMAGE_TAG}} .

# Launch an ephemeral VM and SSH into it
run:
    bcvk ephemeral run-ssh {{IMAGE_NAME}}:{{IMAGE_TAG}}

# Bootstrap the current system directly (non-bootc)
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    DISTRO=$(. /etc/os-release && echo "$ID")
    if command -v dnf &>/dev/null; then
        PACKAGE_MANAGER=dnf
    elif command -v pacman &>/dev/null; then
        PACKAGE_MANAGER=pacman
    else
        echo "ERROR: Unsupported package manager" >&2; exit 1
    fi
    sudo DISTRO="$DISTRO" PACKAGE_MANAGER="$PACKAGE_MANAGER" bash build-scripts/build.sh
    /usr/libexec/post-deploy
    sudo rm -rf /usr/libexec/post-deploy /usr/libexec/post-deploy.d /usr/share/flatpak-apps.d

# Remove the built image and dangling layers
clean:
    podman rmi -f {{IMAGE_NAME}}:{{IMAGE_TAG}}
    podman image prune -f
