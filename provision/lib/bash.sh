#!/usr/bin/env bash
## Profile.d helpers — add aliases and environment variables to /etc/profile.d/
##
## Usage:
##   bash_alias <group> <name> <command>
##   bash_env   <group> <name> <value>
##
## <group> becomes the script name: /etc/profile.d/<group>.sh
## Multiple calls with the same group append to the same file.
##
## Examples:
##   bash_env   node NODE_OPTIONS "--max-old-space-size=4096"
##
##   bash_alias rust cc "sccache cc"
##   bash_env   rust CARGO_HOME "/opt/cargo"
##   bash_env   rust RUSTC_WRAPPER "sccache"  # appends to the same rust.sh

# Write a single line to a profile.d script (create or append).
_bash_profile_line() {
    local group="$1" line="$2"
    local file="/etc/profile.d/${group}.sh"
    if [[ -f "$file" ]]; then
        fs_append "$file" <<< "$line"
    else
        fs_write "$file" <<< "$line"
    fi
}

# Add an alias to /etc/profile.d/<group>.sh
# Usage: bash_alias <group> <name> <command>
bash_alias() {
    _bash_profile_line "$1" "alias ${2}='${3}'"
}

# Add an exported variable to /etc/profile.d/<group>.sh
# Usage: bash_env <group> <name> <value>
bash_env() {
    _bash_profile_line "$1" "export ${2}='${3}'"
}
