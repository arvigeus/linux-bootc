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

This reconciles your system state, runs all build modules, and executes post-deploy scripts (Flatpak apps, VS Code extensions, etc.).

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

### Build modules

System configuration lives in `provision/modules/` as plain bash scripts. Each module installs packages, writes config files, or registers apps — using the distro's native commands (`dnf install`, `pacman -S`, `flatpak install`, etc.).

Modules are sourced in order by `provision/build.sh`. Per-distro variants are supported: `repos/arch.sh` runs on Arch, `repos/fedora.sh` on Fedora, and `repos.sh` would run on both.

### Container mode

`just build` builds an OCI container image via podman. The build scripts run inside the container, installing packages and configuring the system. The result is an immutable image that can be deployed via bootc or written to disk.

Build-time shims validate command syntax but do not record state — no reconciliation is involved. Post-deploy scripts (Flatpak apps, VS Code extensions, etc.) that need a running user session are deferred to first boot via a systemd user service that triggers once per new image deployment.

### Bootstrap mode

`just bootstrap` runs the same build scripts directly on your existing system. Since a live system can drift between runs (manual installs, config edits, removed packages), bootstrap includes a reconciliation system to keep things in check.

**State tracking**: Lightweight [shims](provision/shims/README.md) intercept package manager and config commands during the build to record what was declared into `/usr/share/system-state.d/`. Every package is categorized as either *managed* (declared by build scripts) or *baseline* (everything else that was already on the system).

**Reconciliation** runs automatically before and after the build:

- **Before**: seeds a baseline of your currently installed packages (first run only), merges any config files that have drifted since the last build
- **After**: flags packages removed from build scripts, detects manually installed packages, and verifies config files match

For packages, you choose to install, remove, add to baseline, or ignore. For config files, you can overwrite, accept the current version, merge interactively, or ignore.

You can also run `just reconcile` independently to check system state at any time.

Post-deploy scripts run unconditionally at the end of each bootstrap.

### Declarative Flatpak apps

Flatpak apps can't be installed at build time (they need D-Bus, user sessions, etc.). Modules register apps with familiar syntax, and a post-deploy script handles the actual installation:

```sh
flatpak install --noninteractive --user flathub org.example.App
flatpak app-config org.example.App config/settings.json '{"key": "val"}'
```

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
