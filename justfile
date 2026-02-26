default: build run

image_name := "localhost/my-bootc"
image_tag := "latest"

# Build the bootc container image
build:
    podman build -t {{image_name}}:{{image_tag}} .

# Launch an ephemeral VM and SSH into it
run:
    bcvk ephemeral run-ssh {{image_name}}:{{image_tag}}
