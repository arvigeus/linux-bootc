set dotenv-load

default distro=env("DISTRO", "fedora"): (run distro)

IMAGE_NAME := env("IMAGE_NAME", "linux-bootc")
IMAGE_TAG := env("IMAGE_TAG", "latest")

# Build the bootc container image
build distro:
    podman build -f Containerfile.{{distro}} \
        -t {{IMAGE_NAME}}:{{IMAGE_TAG}} .

# Build and launch an ephemeral VM
run distro=env("DISTRO", "fedora"): (build distro)
    bcvk ephemeral run-ssh {{IMAGE_NAME}}:{{IMAGE_TAG}}

# Reconcile system state against declared state (interactive)
reconcile mode="post":
    sudo bash scripts/reconciliation/reconcile.sh {{mode}}

# Bootstrap the current system directly (non-bootc)
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    # Update system packages
    bash scripts/update.sh
    # Pre-reconciliation: seed base lists, merge drifted configs
    sudo bash scripts/reconciliation/reconcile.sh pre
    # Build (DISTRO and PACKAGE_MANAGER are auto-detected by build.sh)
    sudo bash provision/build.sh
    # Post-reconciliation: flag missing/extra packages, verify configs
    sudo bash scripts/reconciliation/reconcile.sh post

# Lint and format-check all shell scripts
check:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t scripts < <(find . -name '*.sh' -not -path './.git/*')
    shellcheck --severity=warning "${scripts[@]}"
    shfmt --apply-ignore -w "${scripts[@]}"

# Run all tests
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in tests/test-*.sh; do
        echo "=== $t ==="
        bash "$t"
    done

# Remove the built image and dangling layers
clean:
    podman rmi -f {{IMAGE_NAME}}:{{IMAGE_TAG}}
    podman image prune -f
