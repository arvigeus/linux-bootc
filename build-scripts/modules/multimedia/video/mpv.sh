#!/usr/bin/env bash
## mpv media player with shaders and plugins
## https://mpv.io/
set -oue pipefail

# Shader pack install location (replaces ~~/shaders/ in mpv.conf)
SHADERS_DIR="/usr/share/mpv-shim-default-shaders/shaders"
MPV_CONF_DIR="/etc/mpv"

github_latest_tag() {
    curl -sI "https://github.com/$1/releases/latest" | grep -i ^location | sed 's|.*/||;s|\r||'
}

install_shaders() {
    local tag tmpdir
    tag=$(github_latest_tag "iwalton3/default-shader-pack")
    tmpdir=$(mktemp -d)
    curl -L "https://github.com/iwalton3/default-shader-pack/archive/refs/tags/${tag}.tar.gz" \
        | tar -xz --strip-components=1 -C "$tmpdir"
    rm -rf /usr/share/mpv-shim-default-shaders
    install -d /usr/share/mpv-shim-default-shaders
    cp -r "$tmpdir/shaders" /usr/share/mpv-shim-default-shaders/
    cp "$tmpdir"/{pack.json,pack-hq.json,pack-next.json} /usr/share/mpv-shim-default-shaders/
    rm -rf "$tmpdir"
}

install_thumbfast() {
    local tmpdir
    tmpdir=$(mktemp -d)
    curl -L "https://github.com/po5/thumbfast/archive/refs/heads/master.tar.gz" \
        | tar -xz --strip-components=1 -C "$tmpdir"
    install -Dm644 "$tmpdir/thumbfast.lua" "${MPV_CONF_DIR}/scripts/thumbfast.lua"
    install -Dm644 "$tmpdir/thumbfast.conf" "${MPV_CONF_DIR}/script-opts/thumbfast.conf"
    rm -rf "$tmpdir"
}

install_uosc() {
    local tag tmpdir
    tag=$(github_latest_tag "tomasklaen/uosc")
    tmpdir=$(mktemp -d)
    curl -L "https://github.com/tomasklaen/uosc/archive/refs/tags/${tag}.tar.gz" \
        | tar -xz --strip-components=1 -C "$tmpdir"
    (
        cd "$tmpdir"
        CGO_ENABLED=0 GOFLAGS="-modcacherw" go build -o ./ziggy-linux ./src/ziggy/ziggy.go
    )
    rm -rf /usr/share/mpv/scripts/uosc
    install -d /usr/share/mpv/scripts
    cp -a "$tmpdir/src/uosc" /usr/share/mpv/scripts/uosc
    install -Dm755 "$tmpdir/ziggy-linux" /usr/share/mpv/scripts/uosc/bin/ziggy-linux
    install -Dm644 "$tmpdir/src/uosc.conf" "${MPV_CONF_DIR}/script-opts/uosc.conf"
    for font in uosc_icons.otf uosc_textures.ttf; do
        install -Dm644 "$tmpdir/src/fonts/${font}" "/usr/share/mpv/fonts/${font}"
    done
    rm -rf "$tmpdir"
}

packages=(
    mpv
)

# Install packages
case "$PACKAGE_MANAGER" in
    dnf)
        dnf install -y "${packages[@]}"
        # golang is a build dependency for uosc's ziggy binary
        _had_golang=$(command -v go &>/dev/null && echo 1 || echo 0)
        [[ $_had_golang -eq 0 ]] && dnf install -y golang
        install_shaders
        install_thumbfast
        install_uosc
        [[ $_had_golang -eq 0 ]] && dnf remove -y golang
        ;;
    pacman)
        packages+=(
            mpv-shim-default-shaders
            chaotic-aur/mpv-uosc-git
            chaotic-aur/mpv-thumbfast-git
        )
        pacman -S --noconfirm --needed "${packages[@]}"
        ;;
esac

# Download sosc (seasonal OSC)
mkdir -p "${MPV_CONF_DIR}/scripts"
curl -L -o "${MPV_CONF_DIR}/scripts/osc.lua" \
    "https://raw.githubusercontent.com/christoph-heinrich/sosc/master/osc.lua"

# Write global mpv.conf
mkdir -p "${MPV_CONF_DIR}"
cat > "${MPV_CONF_DIR}/mpv.conf" << EOF
# UI
autofit=70%
osc=no
script-opts-append=uosc-disable_elements=idle_indicator

# Video
vo=gpu-next
gpu-api=vulkan
hwdec=auto-safe

# Audio
ao=pipewire
alang=jpn,jp,eng,en
volume-max=300

# Subtitles
slang=eng,en,bg,vi,vn
sub-auto=fuzzy

# Screenshots
screenshot-directory=~/Pictures
screenshot-template=mpv-%f-%wH.%wM.%wS.%wT-#%#00n

# Profiles
profile=generic-high

# https://github.com/iwalton3/default-shader-pack/blob/master/pack-next.json

[fsr]
glsl-shader=${SHADERS_DIR}/FSR.glsl

[cas]
glsl-shader=${SHADERS_DIR}/CAS-scaled.glsl

[fsr-cas]
glsl-shaders=${SHADERS_DIR}/FSR.glsl
glsl-shaders-append=${SHADERS_DIR}/CAS-scaled.glsl

[generic]
dscale=mitchell
cscale=mitchell
glsl-shaders=${SHADERS_DIR}/FSRCNNX_x2_16-0-4-1.glsl
glsl-shaders-append=${SHADERS_DIR}/SSimDownscaler.glsl
glsl-shaders-append=${SHADERS_DIR}/KrigBilateral.glsl

[generic-high]
dscale=mitchell
cscale=mitchell
glsl-shaders=${SHADERS_DIR}/FSRCNNX_x2_8-0-4-1.glsl
glsl-shaders-append=${SHADERS_DIR}/SSimDownscaler.glsl
glsl-shaders-append=${SHADERS_DIR}/KrigBilateral.glsl

[nnedi-high]
dscale=mitchell
cscale=mitchell
glsl-shaders=${SHADERS_DIR}/nnedi3-nns64-win8x6.hook;
glsl-shaders-append=${SHADERS_DIR}/SSimDownscaler.glsl
glsl-shaders-append=${SHADERS_DIR}/KrigBilateral.glsl

[nnedi-very-high]
dscale=mitchell
cscale=mitchell
glsl-shaders=${SHADERS_DIR}/nnedi3-nns128-win8x6.hook;
glsl-shaders-append=${SHADERS_DIR}/SSimDownscaler.glsl
glsl-shaders-append=${SHADERS_DIR}/KrigBilateral.glsl

[anime4k-high-a]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl

[anime4k-high-b]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/CAS-scaled.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_Soft_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl

[anime4k-high-c]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl

[anime4k-high-aa]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/CAS-scaled.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl

[anime4k-high-bb]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_Soft_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_Soft_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl

[anime4k-high-ca]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl

[anime4k-fast-a]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_S.glsl

[anime4k-fast-b]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_Soft_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_S.glsl

[anime4k-fast-c]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_Denoise_CNN_x2_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_S.glsl

[anime4k-fast-aa]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_S.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_S.glsl

[anime4k-fast-bb]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_Soft_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_Soft_S.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_S.glsl

[anime4k-fast-cc]
glsl-shaders=${SHADERS_DIR}/Anime4K_Clamp_Highlights.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_Denoise_CNN_x2_M.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x2.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_AutoDownscalePre_x4.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Restore_CNN_S.glsl
glsl-shaders-append=${SHADERS_DIR}/Anime4K_Upscale_CNN_x2_S.glsl
EOF

# Write global input.conf
cat > "${MPV_CONF_DIR}/input.conf" << 'EOF'
MBTN_LEFT no-osd cycle pause
MOUSE_BTN2 script-binding uosc/menu-blurred
tab script-binding uosc/toggle-ui
Shift+ENTER script-binding uosc/download-subtitles

` script-binding console/enable #! Console

g cycle interpolation #! Video > Interpolation
d cycle deinterlace #! Video > Toggle Deinterlace
[ add speed +0.1; script-binding uosc/flash-speed #! Video > Speed > Increase Speed
] add speed -0.1; script-binding uosc/flash-speed #! Video > Speed > Decrease Speed
BS set speed 1; script-binding uosc/flash-speed #! Video > Speed > Reset Speed
# set video-aspect-override "-1" #! Video > Aspect Ratio > Default
# set video-aspect-override "16:9" #! Video > Aspect Ratio > 16:9
# set video-aspect-override "4:3" #! Video > Aspect Ratio > 4:3
# set video-aspect-override "2.35:1" #! Video > Aspect Ratio > 2.35:1
# vf toggle vflip #! Video > Flip > Vertical
# vf toggle hflip #! Video > Flip > Horizontal
b cycle-values deband "yes" "no" #! Video > Deband > Toggle Deband
# cycle-values deband-threshold "35" "45" "60\ show-text "Deband: ${deband-iterations}:${deband-threshold}:${deband-range}:${deband-grain}" 1000 #! Video > Deband > Deband (Weak)
# cycle-values deband-range "20" "25" "30\ show-text "Deband: ${deband-iterations}:${deband-threshold}:${deband-range}:${deband-grain}" 1000 #! Video > Deband > Deband (Medium)
# cycle-values deband-grain "5" "15" "30\ show-text "Deband: ${deband-iterations}:${deband-threshold}:${deband-range}:${deband-grain}" 1000 #! Video > Deband > Deband (Strong)

# script-binding uosc/audio-device #! Audio > Devices
F1 af toggle "lavfi=[loudnorm=I=-14:TP=-3:LRA=4]'"; show-text "${af}" #! Audio > Dialogue
# af clr "" #! Audio > Clear Filters
# script-binding afilter/toggle-eqr #! Audio > Toggle Equalizer
a cycle audio-normalize-downmix #! Audio > Toggle Normalize
# script-binding afilter/toggle-dnm #! Audio > Toggle Normalizer
# script-binding afilter/toggle-drc #! Audio > Toggle Compressor
Ctrl++ add audio-delay +0.10 #! Audio > Delay > Increase Audio Delay
Ctrl+- add audio-delay -0.10 #! Audio > Delay > Decrease Audio Delay
# set audio-delay 0 #! Audio > Delay > Reset Audio Delay

Shift+g add sub-scale +0.05 #! Subtitles > Scale > Increase Subtitle Scale
Shift+f add sub-scale -0.05 #! Subtitles > Scale > Decrease Subtitle Scale
# set sub-scale 1 #! Subtitles > Scale > Reset Subtitle Scale
: add sub-pos -1 #! Subtitles > Position > Move Subtitle Up
" add sub-pos +1 #! Subtitles > Position > Move Subtitle Down
# set sub-pos 100 #! Subtitles > Position > Reset Subtitle Position
z add sub-delay -0.1 #! Subtitles > Delay > Decrease Subtitles Delay
Z add sub-delay 0.1 #! Subtitles > Delay > Increase Subtitles Delay
# set sub-delay 0 #! Subtitles > Delay > Reset Subtitles Delay

# script-binding sview/shader-view #! Profiles > Show Loaded Shaders
CTRL+0 change-list glsl-shaders clr all; show-text "Shaders cleared" #! Profiles > Clear All Shaders
# #! Profiles > ---
# apply-profile fsr; show-text "Profile: AMD FidelityFX Super Resolution" #! Profiles > AMD FidelityFX Super Resolution
# apply-profile cas; show-text "Profile: AMD FidelityFX Contrast Adaptive Sharpening" #! Profiles > AMD FidelityFX Contrast Adaptive Sharpening
CTRL+1 apply-profile fsr-cas; show-text "Profile: AMD FidelityFX Super Resolution + Contrast Adaptive Sharpening" #! Profiles > AMD FidelityFX Super Resolution + Contrast Adaptive Sharpening
# apply-profile generic #! Profiles > FSRCNNX
CTRL+2 apply-profile generic-high; show-text "Profile: FSRCNNX x16" #! Profiles > FSRCNNX x16
# apply-profile nnedi-high; show-text "Profile: NNEDI3 (64 Neurons)" #! Profiles > NNEDI3 (64 Neurons)
CTRL+3 apply-profile nnedi-very-high; show-text "Profile: NNEDI3 High (128 Neurons)" #! Profiles > NNEDI3 High (128 Neurons)
CTRL+4 apply-profile anime4k-high-a; show-text "Profile: Anime4K A (HQ) - For Very Blurry/Compressed" #! Profiles > Anime4K A (HQ) - For Very Blurry/Compressed
CTRL+5 apply-profile anime4k-high-b; show-text "Profile: Anime4K B (HQ) - For Blurry/Ringing" #! Profiles > Anime4K B (HQ) - For Blurry/Ringing
CTRL+6 apply-profile anime4k-high-c; show-text "Profile: Anime4K C (HQ) - For Crisp/Sharp" #! Profiles > Anime4K C (HQ) - For Crisp/Sharp
CTRL+7 apply-profile anime4k-high-aa; show-text "Profile: Anime4K AA (HQ) - For Very Blurry/Compressed" #! Profiles > Anime4K AA (HQ) - For Very Blurry/Compressed
CTRL+8 apply-profile anime4k-high-bb; show-text "Profile: Anime4K BB (HQ) - For Blurry/Ringing" #! Profiles > Anime4K BB (HQ) - For Blurry/Ringing
CTRL+9 apply-profile anime4k-high-ca; show-text "Profile: Anime4K CA (HQ) - For Crisp/Sharp" #! Profiles > Anime4K CA (HQ) - For Crisp/Sharp
# apply-profile anime4k-fast-a; show-text "Profile: Anime4K A (Fast) - For Very Blurry/Compressed" #! Profiles > Anime4K A (Fast) - For Very Blurry/Compressed
# apply-profile anime4k-fast-b; show-text "Profile: Anime4K B (Fast) - For Blurry/Ringing" #! Profiles > Anime4K B (Fast) - For Blurry/Ringing
# apply-profile anime4k-fast-c; show-text "Profile: Anime4K C (Fast) - For Crisp/Sharp" #! Profiles > Anime4K C (Fast) - For Crisp/Sharp
# apply-profile anime4k-fast-aa; show-text "Profile: Anime4K AA (Fast) - For Very Blurry/Compressed" #! Profiles > Anime4K AA (Fast) - For Very Blurry/Compressed
# apply-profile anime4k-fast-bb; show-text "Profile: Anime4K BB (Fast) - For Blurry/Ringing" #! Profiles > Anime4K BB (Fast) - For Blurry/Ringing
# apply-profile anime4k-fast-cc; show-text "Profile: Anime4K CA (Fast) - For Crisp/Sharp" #! Profiles > Anime4K CA (Fast) - For Crisp/Sharp
EOF
