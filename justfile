set dotenv-load

default: build run

DISTRO := env("DISTRO", "fedora")

IMAGE_NAME := env("IMAGE_NAME", "linux-bootc")
IMAGE_TAG := env("IMAGE_TAG", "latest")

# Build the bootc container image
build:
    podman build -f Containerfile.{{DISTRO}} --build-arg DISTRO={{DISTRO}} -t {{IMAGE_NAME}}:{{IMAGE_TAG}} .

# Launch an ephemeral VM and SSH into it
run:
    bcvk ephemeral run-ssh {{IMAGE_NAME}}:{{IMAGE_TAG}}

# Remove the built image and dangling layers
clean:
    podman rmi -f {{IMAGE_NAME}}:{{IMAGE_TAG}}
    podman image prune -f
