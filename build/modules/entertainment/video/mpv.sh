#!/usr/bin/env bash
## mpv media player with shaders and plugins
## https://mpv.io/
set -oue pipefail

# Configuration
SHADERS_DIR="/usr/share/mpv-shim-default-shaders/shaders"
PACK_JSON="/usr/share/mpv-shim-default-shaders/pack-next.json"
MPV_CONF_DIR="/etc/mpv"

packages=(
    mpv
)

# --- Static config files ---

mkdir -p "${MPV_CONF_DIR}"

# mpv.conf
cat > "${MPV_CONF_DIR}/mpv.conf" << 'EOF'
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
EOF

# input.conf
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
CTRL+1 apply-profile fsr-cas; show-text "Profile: AMD FidelityFX SR + CAS" #! Profiles > AMD FidelityFX SR + CAS
CTRL+2 apply-profile generic-high; show-text "Profile: FSRCNNX x16" #! Profiles > FSRCNNX x16
CTRL+3 apply-profile nnedi-very-high; show-text "Profile: NNEDI3 High (128 Neurons)" #! Profiles > NNEDI3 High (128 Neurons)
CTRL+4 apply-profile anime4k-high-a; show-text "Profile: Anime4K A (HQ) - For Very Blurry/Compressed" #! Profiles > Anime4K A (HQ) - For Very Blurry/Compressed
CTRL+5 apply-profile anime4k-high-b; show-text "Profile: Anime4K B (HQ) - For Blurry/Ringing" #! Profiles > Anime4K B (HQ) - For Blurry/Ringing
CTRL+6 apply-profile anime4k-high-c; show-text "Profile: Anime4K C (HQ) - For Crisp/Sharp" #! Profiles > Anime4K C (HQ) - For Crisp/Sharp
CTRL+7 apply-profile anime4k-high-aa; show-text "Profile: Anime4K AA (HQ) - For Very Blurry/Compressed" #! Profiles > Anime4K AA (HQ) - For Very Blurry/Compressed
CTRL+8 apply-profile anime4k-high-bb; show-text "Profile: Anime4K BB (HQ) - For Blurry/Ringing" #! Profiles > Anime4K BB (HQ) - For Blurry/Ringing
CTRL+9 apply-profile anime4k-high-ca; show-text "Profile: Anime4K CA (HQ) - For Crisp/Sharp" #! Profiles > Anime4K CA (HQ) - For Crisp/Sharp
EOF

# --- Functions ---

# https://gitlab.archlinux.org/archlinux/packaging/packages/mpv-shim-default-shaders/-/blob/main/PKGBUILD
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

# https://gitlab.com/chaotic-aur/pkgbuilds/-/blob/main/mpv-thumbfast-git/PKGBUILD
install_thumbfast() {
    local tmpdir
    tmpdir=$(mktemp -d)
    curl -L "https://github.com/po5/thumbfast/archive/refs/heads/master.tar.gz" \
        | tar -xz --strip-components=1 -C "$tmpdir"
    install -Dm644 "$tmpdir/thumbfast.lua" "${MPV_CONF_DIR}/scripts/thumbfast.lua"
    install -Dm644 "$tmpdir/thumbfast.conf" "${MPV_CONF_DIR}/script-opts/thumbfast.conf"
    rm -rf "$tmpdir"
}

# https://github.com/stax76/awesome-mpv?tab=readme-ov-file#on-screen-controller
# https://gitlab.com/chaotic-aur/pkgbuilds/-/blob/main/mpv-uosc/PKGBUILD
install_osc() {
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

# --- Install packages ---

case "$PACKAGE_MANAGER" in
    dnf)
        dnf install -y "${packages[@]}"
        # golang is a build dependency for uosc's ziggy binary
        _had_golang=$(command -v go &>/dev/null && echo 1 || echo 0)
        [[ $_had_golang -eq 0 ]] && dnf install -y golang
        install_shaders
        install_thumbfast
        install_osc
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

# --- Additional plugins ---

# Download sosc (seasonal OSC)
mkdir -p "${MPV_CONF_DIR}/scripts"
curl -L -o "${MPV_CONF_DIR}/scripts/osc.lua" \
    "https://raw.githubusercontent.com/christoph-heinrich/sosc/master/osc.lua"

# --- Append auto-generated config (requires pack-next.json from install) ---

# Ensure pack-next.json is available for config generation
if [[ ! -f "$PACK_JSON" ]]; then
    curl -sL "https://raw.githubusercontent.com/iwalton3/default-shader-pack/master/pack-next.json" \
        -o "$PACK_JSON"
fi

# Generate mpv profile sections from upstream pack-next.json
echo '# Auto-generated from https://github.com/iwalton3/default-shader-pack/blob/master/pack-next.json' >> "${MPV_CONF_DIR}/mpv.conf"
jq -r --arg sd "${SHADERS_DIR}" '
    .["setting-groups"] as $g |
    .profiles | to_entries[] |
    .key as $n | .value as $p |
    ($p["setting-groups"] // []) as $sgs |
    ([($sgs[] | $g[.].shaders // [] | .[])] + ($p.shaders // [])) as $shaders |
    [($sgs[] | $g[.].settings // [] | .[])] as $settings |
    "[\($n)]",
    ($settings[] |
        "\(.[0] | gsub("_"; "-"))=\(
            if .[1] == true then "yes"
            elif .[1] == false then "no"
            else .[1] | tostring
            end
        )"
    ),
    ($shaders | to_entries[] |
        if .key == 0 then "glsl-shaders=\($sd)/\(.value)"
        else "glsl-shaders-append=\($sd)/\(.value)"
        end
    ),
    ""
' "${PACK_JSON}" >> "${MPV_CONF_DIR}/mpv.conf"

# Convenience aliases for long profile names
cat >> "${MPV_CONF_DIR}/mpv.conf" << 'EOF'
[fsr]
profile=AMD FidelityFX Super Resolution

[cas]
profile=AMD FidelityFX Contrast Adaptive Sharpening

EOF

# Custom combo profile (not in upstream shader pack)
cat >> "${MPV_CONF_DIR}/mpv.conf" << EOF
[fsr-cas]
glsl-shaders=${SHADERS_DIR}/FSR.glsl
glsl-shaders-append=${SHADERS_DIR}/CAS-scaled.glsl
EOF

# Generate input.conf menu entries for profiles without manual keybindings
BOUND_PROFILES="fsr-cas generic-high nnedi-very-high anime4k-high-a anime4k-high-b anime4k-high-c anime4k-high-aa anime4k-high-bb anime4k-high-ca"
jq -r --arg skip "$BOUND_PROFILES" '
    ($skip | split(" ")) as $skip_list |
    .profiles | to_entries[] |
    select(.key as $k | $skip_list | index($k) | not) |
    "# apply-profile \"\(.key)\"; show-text \"Profile: \(.value.displayname // .key)\" #! Profiles > \(.value.displayname // .key)"
' "${PACK_JSON}" >> "${MPV_CONF_DIR}/input.conf"
