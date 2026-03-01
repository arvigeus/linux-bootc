FROM quay.io/fedora/fedora-bootc:43

RUN \
    ## Enable RPM Fusion repositories (free + nonfree) \
    ## https://rpmfusion.org/ \
    dnf install -y \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    \
    ## Enable Terra repository \
    ## https://terra.fyralabs.com/ \
    dnf install -y --nogpgcheck \
        --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
        terra-release && \
    \
    ## Enable Copr repositories \
    ## https://copr.fedorainfracloud.org/ \
    # for copr in \
    #     <user>/<project>   `# Comment` \
    # ; do \
    #     dnf copr enable -y $copr; \
    # done && unset -v copr && \
    \
    ## Flathub support \
    ## Drops the remote config so flatpak picks it up automatically \
    mkdir -p /etc/flatpak/remotes.d && \
    curl --retry 3 -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
        https://dl.flathub.org/repo/flathub.flatpakrepo && \
    \
    ## Media codecs (requires RPM Fusion) \
    ## https://rpmfusion.org/Howto/Multimedia \
    dnf swap -y ffmpeg-free ffmpeg --allowerasing && \
    dnf group install -y multimedia sound-and-video \
        --setopt="install_weak_deps=False" \
        --exclude=PackageKit-gstreamer-plugin && \
    \
    ## AppImage support \
    dnf install -y fuse-libs && \
    \
    ## Cleanup \
    dnf clean all

# https://bootc-dev.github.io/bootc/bootc-images.html#standard-metadata-for-bootc-compatible-images
LABEL containers.bootc 1

RUN bootc container lint
