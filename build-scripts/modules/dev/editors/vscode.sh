#!/usr/bin/env bash
## Visual Studio Code
## https://code.visualstudio.com/
set -oue pipefail

packages=(
    code
)

# Base VSCode settings (extension-specific settings are merged later)
read -r -d '' base_settings << 'EOF' || true
{
  "update.mode": "none",
  "window.titleBarStyle": "custom",
  "workbench.colorTheme": "One Dark Pro Mix",
  "editor.fontFamily": "'FiraCode Nerd Font', 'FiraCode Nerd Font Mono', 'monospace', monospace",
  "editor.inlineSuggest.enabled": true,

  "git.autofetch": true,
  "git.confirmSync": false,
  "git.enableCommitSigning": true
}
EOF

# Key: extension name; Value: settings
declare -A extensions=(
    # Essentials
    [mikestead.dotenv]=''
    [editorconfig.editorconfig]=''

    # Interface Improvements
    [eamodio.gitlens]=''
    [usernamehw.errorlens]='{
	  "errorLens.gutterIconsEnabled": true,
      "errorLens.messageMaxChars": 0
	}'
    [pflannery.vscode-versionlens]=''
    [yoavbls.pretty-ts-errors]=''
    [wix.vscode-import-cost]=''
    [gruntfuggly.todo-tree]='{
      "todo-tree.highlights.customHighlight": {
        "TODO": {
          "type": "text",
          "foreground": "#000000",
          "background": "#00FF00",
          "iconColour": "#00FF00",
          "icon": "shield-check",
          "gutterIcon": true
        },
        "FIXME": {
          "type": "text",
          "foreground": "#000000",
          "background": "#FFFF00",
          "iconColour": "#FFFF00",
          "icon": "shield",
          "gutterIcon": true
        },
        "HACK": {
          "type": "text",
          "foreground": "#000000",
          "background": "#FF0000",
          "iconColour": "#FF0000",
          "icon": "shield-x",
          "gutterIcon": true
        },
        "BUG": {
          "type": "text",
          "foreground": "#000000",
          "background": "#FFA500",
          "iconColour": "#FFA500",
          "icon": "bug",
          "gutterIcon": true
        }
      }
    }'

    # AI
    [RooVeterinaryInc.roo-cline]=''
    [Anthropic.claude-code]=''

    # Color schemes (workbench.colorTheme: "One Dark Pro Mix")
    [zhuangtongfa.material-theme]=''

    # Docker (Podman)
    [docker.docker]=''

    # Web Dev
    [biomejs.biome]='{
      "[html]": { "editor.defaultFormatter": "biomejs.biome" },
      "[css]": { "editor.defaultFormatter": "biomejs.biome" },
      "[javascript]": { "editor.defaultFormatter": "biomejs.biome" },
      "[json]": { "editor.defaultFormatter": "biomejs.biome" },
      "[jsonc]": { "editor.defaultFormatter": "biomejs.biome" },
      "[typescript]": { "editor.defaultFormatter": "biomejs.biome" },
      "[typescriptreact]": { "editor.defaultFormatter": "biomejs.biome" }
    }'
    [dbaeumer.vscode-eslint]=''
    [esbenp.prettier-vscode]='{
      "[markdown]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
      "[scss]": { "editor.defaultFormatter": "esbenp.prettier-vscode" }
    }'
    [csstools.postcss]=''
    [stylelint.vscode-stylelint]=''
    [bradlc.vscode-tailwindcss]=''
    [davidanson.vscode-markdownlint]=''
    [unifiedjs.vscode-mdx]=''

    # Deno
    [denoland.vscode-deno]=''

    # GraphQL
    [graphql.vscode-graphql-syntax]=''
    [graphql.vscode-graphql]=''

    # Bash
    [mads-hartmann.bash-ide-vscode]='{
	  "bashIde.shellcheckPath": "/usr/bin/shellcheck"
	}'
    [mkhl.shfmt]='{
	  "shfmt.executablePath": "/usr/bin/shfmt"
	}'

    # Rust
    [rust-lang.rust-analyzer]=''
    [vadimcn.vscode-lldb]=''
    [wcrichton.flowistry]=''

    # TOML
    [tamasfe.even-better-toml]=''

    # Just
    [nefrob.vscode-just-syntax]=''

    # Testing
    [vitest.explorer]=''
    [ms-playwright.playwright]=''
    [firefox-devtools.vscode-firefox-debug]=''
    [ms-vscode.test-adapter-converter]=''
)

# Merge base settings with all extension settings
vscode_settings="$base_settings"
for ext in "${!extensions[@]}"; do
    if [[ -n "${extensions[$ext]}" ]]; then
        vscode_settings=$(printf '%s\n%s' "$vscode_settings" "${extensions[$ext]}" | jq -s '.[0] * .[1]')
    fi
done

# Install packages
case "$PACKAGE_MANAGER" in
    dnf)
        # https://code.visualstudio.com/docs/setup/linux#_rhel-fedora-and-centos-based-distributions
        rpm --import https://packages.microsoft.com/keys/microsoft.asc
        cat > /etc/yum.repos.d/vscode.repo << 'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
        dnf install -y "${packages[@]}"
        CODE_CONF_DIR="Code"
        ;;
    pacman)
        pacman -S --noconfirm --needed "${packages[@]}"
        CODE_CONF_DIR="Code - OSS"
        ;;
esac

# Build-time values (CODE_CONF_DIR, settings, extensions) are baked in, then quoted heredoc for logic
VSCODE_SCRIPT="$POST_DEPLOY_DIR/50-vscode-extensions.sh"
{
    echo '#!/usr/bin/env bash'
    echo "CODE_CONF_DIR='${CODE_CONF_DIR}'"
    echo "extensions=("
    printf '    %s\n' "${!extensions[@]}"
    echo ")"
    echo "read -r -d '' VSCODE_SETTINGS << 'SETTINGS_EOF' || true"
    echo "$vscode_settings"
    echo "SETTINGS_EOF"
} > "$VSCODE_SCRIPT"
cat >> "$VSCODE_SCRIPT" << 'EXTSCRIPT'
set -euo pipefail

SETTINGS_DIR="$HOME/.config/${CODE_CONF_DIR}/User"
mkdir -p "$SETTINGS_DIR"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$VSCODE_SETTINGS") > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
else
    echo "$VSCODE_SETTINGS" | jq . > "$SETTINGS_FILE"
fi

for ext in "${extensions[@]}"; do
    code --install-extension "$ext"
done
EXTSCRIPT
chmod +x "$VSCODE_SCRIPT"
