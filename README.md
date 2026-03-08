# linux-bootc

A modular Linux build system that supports two modes:

- **bootc image**: builds an immutable OCI container image deployable via [bootc](https://docs.fedoraproject.org/en-US/bootc/)
- **System bootstrap**: runs the same build scripts directly on an existing Fedora or Arch installation

Build modules are shared between both modes — the `PACKAGE_MANAGER` and `/run/.containerenv` checks handle the differences.

## Prerequisites

| Dependency                                          | Purpose                                                              |
| --------------------------------------------------- | -------------------------------------------------------------------- |
| [podman](https://podman.io/)                        | Builds the container image                                           |
| [qemu](https://www.qemu.org/)                       | Runs the VM (used by bcvk under the hood)                            |
| [virtiofsd](https://gitlab.com/virtio-fs/virtiofsd) | Shares filesystems between host and VM                               |
| [edk2-ovmf](https://github.com/tianocore/edk2)      | UEFI firmware for the VM                                             |
| [just](https://just.systems/)                       | Task runner                                                          |
| [bcvk](https://github.com/bootc-dev/bcvk)           | Launches ephemeral VMs from bootc containers and creates disk images |

### Arch Linux

```sh
sudo pacman -S --needed podman qemu-full virtiofsd edk2-ovmf just
```

Install bcvk from the AUR:

```sh
paru -S bootc-bcvk  # or yay -S bootc-bcvk
```

Alternatively, install via Cargo:

```sh
cargo install --locked --git https://github.com/bootc-dev/bcvk bcvk
```

### Fedora

```sh
sudo dnf install podman qemu-kvm virtiofsd edk2-ovmf just bcvk
```

## Usage

Build the container image and launch an ephemeral VM:

```sh
just
```

This runs `just build` followed by `just run`, which builds the image with podman and drops you into an SSH session inside the VM via bcvk. The VM is cleaned up automatically when you exit.

> **Note:** You may see `bootloader-update.service` listed as a failed unit. This is expected — the ephemeral VM has no persistent bootloader to update.

You can also run the steps individually:

```sh
just build   # Build the container image
just run     # Launch VM and SSH in
```

## Post-deploy scripts

Some setup (VS Code extensions, Flatpak apps) can't run at image build time — it requires a running user session. The post-deploy system handles this:

- Build modules drop executable scripts into `/usr/libexec/post-deploy.d/`
- **bootc mode**: a systemd user service runs `/usr/libexec/post-deploy` on login, which checks the current image digest against a stored value. Scripts only run once per new image deployment.
- **Bootstrap mode**: `/usr/libexec/post-deploy` runs all scripts unconditionally (called at end of build).

### Declarative Flatpak apps

Flatpak apps can't be installed during image build (they need D-Bus, user sessions, etc.). A build-time shim intercepts `flatpak install` calls in modules and generates [preinstall.d](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall) INI files. A post-deploy script reads these at first boot to do the real installation.

In modules, register apps with familiar `flatpak install` syntax. To provision default config files into `~/.var/app/<app>/` on first boot, use the custom `app-config` subcommand:

```sh
flatpak install --noninteractive --user <remote> <app>
flatpak app-config <app> config/settings.json '{"key": "val"}'
```

## Creating a disk image

bcvk can create bootable disk images (raw or qcow2) from your container image:

```sh
bcvk to-disk localhost/my-bootc:latest disk.raw
bcvk to-disk --format=qcow2 localhost/my-bootc:latest disk.qcow2
```

This can be written to a drive for bare metal installation (e.g. `sudo dd if=disk.raw of=/dev/sdX bs=4M status=progress`).

For other formats (ISO, AMI, VMDK), see [bootc-image-builder](https://github.com/osbuild/bootc-image-builder).

## References

- [Fedora bootc documentation](https://docs.fedoraproject.org/en-US/bootc/)
- [Fedora bootc examples](https://gitlab.com/fedora/bootc/examples)
- [Fedora 43 Post Install Guide](https://github.com/devangshekhawat/Fedora-43-Post-Install-Guide)
- [Zena Linux](https://github.com/Zena-Linux/Zena)
