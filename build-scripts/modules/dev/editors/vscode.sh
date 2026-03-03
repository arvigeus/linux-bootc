#!/usr/bin/env bash
## Visual Studio Code
## https://code.visualstudio.com/
set -oue pipefail

packages=(
    code
)

extensions=(
    # Essentials
    mikestead.dotenv
    editorconfig.editorconfig

    # Interface Improvements
    eamodio.gitlens
    usernamehw.errorlens
    pflannery.vscode-versionlens
    yoavbls.pretty-ts-errors
    wix.vscode-import-cost
    gruntfuggly.todo-tree

    # AI
    RooVeterinaryInc.roo-cline
    Anthropic.claude-code

    # Color schemes (workbench.colorTheme: "One Dark Pro Mix")
    zhuangtongfa.material-theme

    # Docker (Podman)
    docker.docker

    # Web Dev
	biomejs.biome
    dbaeumer.vscode-eslint
    esbenp.prettier-vscode
    csstools.postcss
    stylelint.vscode-stylelint
    bradlc.vscode-tailwindcss
    davidanson.vscode-markdownlint
    unifiedjs.vscode-mdx

    # Deno
    denoland.vscode-deno

    # GraphQL
    graphql.vscode-graphql-syntax
    graphql.vscode-graphql

    # Bash
    mads-hartmann.bash-ide-vscode
    mkhl.shfmt

    # Rust
    rust-lang.rust-analyzer
    vadimcn.vscode-lldb
    wcrichton.flowistry

    # TOML
    tamasfe.even-better-toml

    # Just
    nefrob.vscode-just-syntax

    # Testing
    vitest.explorer
    ms-playwright.playwright
    firefox-devtools.vscode-firefox-debug
    ms-vscode.test-adapter-converter
)

# JSON uses double quotes only, so single-quote wrapping is safe
read -r -d '' vscode_settings << 'EOF' || true
{
  "update.mode": "none",
  "window.titleBarStyle": "custom",
  "workbench.colorTheme": "One Dark Pro Mix",
  "editor.fontFamily": "'FiraCode Nerd Font', 'FiraCode Nerd Font Mono', 'monospace', monospace",
  "editor.inlineSuggest.enabled": true,

  "git.autofetch": true,
  "git.confirmSync": false,
  "git.enableCommitSigning": true,

  "[html]": { "editor.defaultFormatter": "biomejs.biome" },
  "[css]": { "editor.defaultFormatter": "biomejs.biome" },
  "[markdown]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[javascript]": { "editor.defaultFormatter": "biomejs.biome" },
  "[json]": { "editor.defaultFormatter": "biomejs.biome" },
  "[jsonc]": { "editor.defaultFormatter": "biomejs.biome" },
  "[scss]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[typescript]": { "editor.defaultFormatter": "biomejs.biome" },
  "[typescriptreact]": { "editor.defaultFormatter": "biomejs.biome" },

  "bashIde.shellcheckPath": "/usr/bin/shellcheck",
  "shfmt.executablePath": "/usr/bin/shfmt",

  "errorLens.gutterIconsEnabled": true,
  "errorLens.messageMaxChars": 0,

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
}
EOF

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
{
    echo '#!/usr/bin/env bash'
    echo "CODE_CONF_DIR='${CODE_CONF_DIR}'"
    echo "VSCODE_SETTINGS='${vscode_settings}'"
    echo "extensions=("
    printf '    %s\n' "${extensions[@]}"
    echo ")"
} > /usr/libexec/post-deploy.d/10-vscode-extensions.sh
cat >> /usr/libexec/post-deploy.d/10-vscode-extensions.sh << 'EXTSCRIPT'
set -euo pipefail

SETTINGS_DIR="$HOME/.config/${CODE_CONF_DIR}/User"
mkdir -p "$SETTINGS_DIR"
echo "$VSCODE_SETTINGS" > "$SETTINGS_DIR/settings.json"

for ext in "${extensions[@]}"; do
    code --install-extension "$ext"
done
EXTSCRIPT
chmod +x /usr/libexec/post-deploy.d/10-vscode-extensions.sh
