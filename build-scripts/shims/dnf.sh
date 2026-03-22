#!/usr/bin/env bash
## DNF build-time shim
##
## Shadows `/usr/bin/dnf` as a bash function so that modules can write
## natural-looking dnf commands. The real binary runs first; on success,
## the operation is recorded for later reconciliation.
##
## In container builds, commands are validated and executed but state
## is not recorded.
##
## Intercepted subcommands:
##
##   dnf install -y <packages...>     — record to dnf.list (repo RPMs via pkg_shim_add_repo)
##   dnf remove  -y <packages...>     — remove from dnf.list
##   dnf swap    -y <old> <new> ...   — remove old, add new to dnf.list
##   dnf group install -y <group> ... — record @<group> to dnf.list
##   dnf copr enable -y <id>          — record via pkg_shim_add_repo "dnf-copr"
##
## Everything else passes through to /usr/bin/dnf.

# Flags whose value is a separate argument (must consume the next arg too).
_DNF_SHIM_VALUE_FLAGS=(--repofrompath --setopt --exclude --repo)

dnf() {
    case "${1:-}" in
        install)  _dnf_shim_install "$@" ;;
        remove)   _dnf_shim_remove "$@" ;;
        swap)     _dnf_shim_swap "$@" ;;
        group)    _dnf_shim_group "$@" ;;
        copr)     _dnf_shim_copr "$@" ;;
        *)        /usr/bin/dnf "$@" ;;
    esac
}

# ── helpers ───────────────────────────────────────────────────────────

# _dnf_shim_extract_packages <args...>
# Like pkg_shim_extract_packages but aware of --flag <value> pairs.
# Skips the subcommand (first positional arg). Prints one package per line.
_dnf_shim_extract_packages() {
    local skip_first=true
    local skipped=false
    local skip_next=false

    for arg in "$@"; do
        if $skip_next; then
            skip_next=false
            continue
        fi

        # Check for value-taking flags
        local is_value_flag=false
        for vf in "${_DNF_SHIM_VALUE_FLAGS[@]}"; do
            if [[ "$arg" == "$vf" ]]; then
                is_value_flag=true
                skip_next=true
                break
            fi
            # Handle --flag=value form
            if [[ "$arg" == "${vf}="* ]]; then
                is_value_flag=true
                break
            fi
        done
        $is_value_flag && continue

        # Skip regular flags
        case "$arg" in
            -*) continue ;;
        esac

        # Skip the subcommand (first positional)
        if $skip_first && ! $skipped; then
            skipped=true
            continue
        fi

        echo "$arg"
    done
}

# _dnf_shim_is_repo_rpm <arg>
# Returns 0 if the argument looks like a repo RPM (URL or local .rpm file).
_dnf_shim_is_repo_rpm() {
    case "$1" in
        http://*.rpm|https://*.rpm|/*.rpm|./*.rpm) return 0 ;;
        *) return 1 ;;
    esac
}

# ── subcommand handlers ──────────────────────────────────────────────

# dnf install -y <packages...>
_dnf_shim_install() {
    pkg_shim_require_flags "$*" -y || return 1
    /usr/bin/dnf "$@" || return $?
    [[ -f /run/.containerenv ]] && return 0

    local -a packages=() repo_rpms=()
    while IFS= read -r pkg; do
        if _dnf_shim_is_repo_rpm "$pkg"; then
            repo_rpms+=("$pkg")
        else
            packages+=("$pkg")
        fi
    done < <(_dnf_shim_extract_packages "$@")

    if [[ ${#packages[@]} -gt 0 ]]; then
        pkg_shim_add dnf "${packages[@]}"
    fi

    for rpm in "${repo_rpms[@]}"; do
        pkg_shim_add_repo "dnf-rpm" "$rpm"
    done
}

# dnf remove -y <packages...>
_dnf_shim_remove() {
    pkg_shim_require_flags "$*" -y || return 1
    /usr/bin/dnf "$@" || return $?
    [[ -f /run/.containerenv ]] && return 0

    local -a packages=()
    while IFS= read -r pkg; do
        packages+=("$pkg")
    done < <(_dnf_shim_extract_packages "$@")

    if [[ ${#packages[@]} -gt 0 ]]; then
        pkg_shim_remove dnf "${packages[@]}"
    fi
}

# dnf swap -y <old> <new> [flags...]
_dnf_shim_swap() {
    pkg_shim_require_flags "$*" -y || return 1
    /usr/bin/dnf "$@" || return $?
    [[ -f /run/.containerenv ]] && return 0

    local -a positionals=()
    while IFS= read -r pkg; do
        positionals+=("$pkg")
    done < <(_dnf_shim_extract_packages "$@")

    if [[ ${#positionals[@]} -ge 2 ]]; then
        pkg_shim_remove dnf "${positionals[0]}"
        pkg_shim_add dnf "${positionals[1]}"
    fi
}

# dnf group install -y <group-name> [flags...]
_dnf_shim_group() {
    local subcmd="${2:-}"

    case "$subcmd" in
        install)
            pkg_shim_require_flags "$*" -y || return 1

            # Extract packages, skipping "group" (first positional) via
            # _dnf_shim_extract_packages, then skip "install" (second positional).
            local -a groups=()
            local skipped_install=false
            while IFS= read -r name; do
                if ! $skipped_install; then
                    skipped_install=true
                    continue
                fi
                groups+=("@${name}")
            done < <(_dnf_shim_extract_packages "$@")

            /usr/bin/dnf "$@" || return $?
            [[ -f /run/.containerenv ]] && return 0

            if [[ ${#groups[@]} -gt 0 ]]; then
                pkg_shim_add dnf "${groups[@]}"
            fi
            ;;
        *)
            /usr/bin/dnf "$@"
            ;;
    esac
}

# dnf copr enable -y <copr-id>
_dnf_shim_copr() {
    local subcmd="${2:-}"

    case "$subcmd" in
        enable)
            # Extract positional args: first is "copr", second is "enable", rest are copr IDs
            local -a coprs=()
            local skipped_enable=false
            while IFS= read -r name; do
                if ! $skipped_enable; then
                    skipped_enable=true
                    continue
                fi
                coprs+=("$name")
            done < <(_dnf_shim_extract_packages "$@")

            /usr/bin/dnf "$@" || return $?
            [[ -f /run/.containerenv ]] && return 0

            for copr_id in "${coprs[@]}"; do
                pkg_shim_add_repo "dnf-copr" "$copr_id"
            done
            ;;
        *)
            /usr/bin/dnf "$@"
            ;;
    esac
}
