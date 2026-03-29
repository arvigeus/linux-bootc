# linux-bootc

A modular Linux build system that supports two modes:

- **Container image** — builds an immutable OCI image deployable via [bootc](https://docs.fedoraproject.org/en-US/bootc/)
- **Bootstrap** — runs the same build scripts directly on an existing Fedora or Arch installation

Both modes share the same build modules. Write your system configuration once, deploy it as a container image or apply it to a live system.

## Quick start

Build the container image and launch an ephemeral VM:

```sh
just
```

This builds the image with podman, then drops you into an SSH session inside a VM via bcvk. The VM is cleaned up when you exit.

Or apply the build scripts directly to your current system:

```sh
just bootstrap
```

This reconciles your system state and runs all build modules.

You can also run steps individually:

```sh
just build       # Build the container image
just run         # Launch VM and SSH in
just reconcile   # Reconcile system state only (no build)
```

> **Note:** You may see `bootloader-update.service` listed as a failed unit in the VM. This is expected — the ephemeral VM has no persistent bootloader to update.

## Prerequisites

| Dependency                                          | Purpose                                              |
| --------------------------------------------------- | ---------------------------------------------------- |
| [just](https://just.systems/)                       | Task runner                                          |
| [podman](https://podman.io/)                        | Builds the container image                           |
| [qemu](https://www.qemu.org/)                       | Runs the VM                                          |
| [virtiofsd](https://gitlab.com/virtio-fs/virtiofsd) | Shares filesystems between host and VM               |
| [edk2-ovmf](https://github.com/tianocore/edk2)      | UEFI firmware for the VM                             |
| [bcvk](https://github.com/bootc-dev/bcvk)           | Launches ephemeral VMs from bootc containers         |

### Arch Linux

```sh
sudo pacman -S --needed podman qemu-full virtiofsd edk2-ovmf just
paru -S bootc-bcvk  # or yay -S bootc-bcvk
```

### Fedora

```sh
sudo dnf install podman qemu-kvm virtiofsd edk2-ovmf just bcvk
```

## How it works

**Modules** are bash scripts in `provision/modules/` that declare what your system should look like — packages, config files, apps — using plain bash scripts. [`modules.conf`](provision/modules.conf) controls which modules run and in what order. Both modes run the same scripts.

**[Shims](provision/shims/README.md)** wrap commands like `dnf`, `flatpak`, and `cp` so the same module code works in both modes, with behavior adapting to context.

**Container mode** (`just build`) runs modules inside a podman build, producing an immutable OCI image. Apps that need a live user session (Flatpak, AppImages, VS Code extensions) can't install at build time, so [deploy scripts](provision/deploy/README.md) handle them on first boot — installing what's declared but not yet present, without removing anything.

**Bootstrap mode** (`just bootstrap`) applies the same declaration to your live system. [Reconciliation](scripts/reconciliation/README.md) tracks what modules declare and keeps it in sync between runs. It only ever touches what was previously declared — anything you installed manually is invisible to it. After each build it reports drift and lets you decide: install missing packages, remove undeclared ones, or leave things as-is.

Run `just reconcile` independently to check state without a full build. On first run it seeds a baseline — everything currently installed is recorded as unmanaged and left alone going forward. Modules declare what's managed; remove something from modules later and reconciliation will offer to uninstall it from the system too.

## Internals

- [Shims](provision/shims/README.md) — intercept commands and record declared state
- [Deploy scripts](provision/deploy/README.md) — first-boot setup for container deployments
- [Reconciliation](scripts/reconciliation/README.md) — drift detection and sync for bootstrap
- [Tests](tests/README.md) — automated tests for shims and reconciliation logic

## Creating a disk image

bcvk can create bootable disk images from your container image:

```sh
bcvk to-disk localhost/linux-bootc:latest disk.raw
bcvk to-disk --format=qcow2 localhost/linux-bootc:latest disk.qcow2
```

This can be written to a drive for bare metal installation (e.g. `sudo dd if=disk.raw of=/dev/sdX bs=4M status=progress`).

For other formats (ISO, AMI, VMDK), see [bootc-image-builder](https://github.com/osbuild/bootc-image-builder).

## Testing

The build system's shims and reconciliation logic have automated [tests](tests/README.md):

```sh
bash tests/test-fs-shim.sh && bash tests/test-reconciliation.sh
```

## References

- [Fedora bootc documentation](https://docs.fedoraproject.org/en-US/bootc/)
- [Fedora bootc examples](https://gitlab.com/fedora/bootc/examples)
- [Fedora 43 Post Install Guide](https://github.com/devangshekhawat/Fedora-43-Post-Install-Guide)
- [Zena Linux](https://github.com/Zena-Linux/Zena)
