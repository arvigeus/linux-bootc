#!/usr/bin/env bash
## Pacman build-time shim
##
## Shadows /usr/bin/pacman as a bash function. The real binary runs first;
## on success, the operation is recorded for later reconciliation.
##
## In container builds, commands are validated and executed but state
## is not recorded.
##
## The operation flag (-S, -R, -U, etc.) MUST be the first argument.
## Removal enforces -Rns for clean removal (no orphans, no .pacsave files).

pacman() {
	case "${1:-}" in
	-S*) _pacman_shim_sync "$@" ;;
	-R*) _pacman_shim_remove "$@" ;;
	-U*) _pacman_shim_upgrade "$@" ;;
	-*) /usr/bin/pacman "$@" ;;
	*)
		echo "ERROR: pacman shim: operation flag (-S, -R, -U, etc.) must be the first argument" >&2
		echo "  Got: pacman $*" >&2
		return 1
		;;
	esac
}

_pacman_shim_sync() {
	local op_arg="$1"

	# Collect packages (non-flag positional args, skip the operation flag)
	local -a pkgs=()
	for arg in "${@:2}"; do
		case "$arg" in
		-*) continue ;;
		*) pkgs+=("$arg") ;;
		esac
	done

	if [[ ${#pkgs[@]} -eq 0 ]]; then
		# No packages: check if this is -Syu (upgrade) or bare -Sy (unsafe)
		if [[ "$op_arg" == *u* ]]; then
			# -Syu: system upgrade, pass through without tracking
			/usr/bin/pacman "$@"
			return
		else
			echo "ERROR: pacman shim: bare -Sy without packages is unsafe." >&2
			echo "  Use -Syu for system upgrade, or -S <packages> to install." >&2
			return 1
		fi
	fi

	# Has packages — validate required flags
	pkg_shim_require_flags "$*" --noconfirm --needed || return 1

	# Strip repo prefix (e.g., "chaotic-aur/paru" → "paru") for the manifest,
	# but pass original args to pacman unchanged
	local -a clean_pkgs=()
	for pkg in "${pkgs[@]}"; do
		clean_pkgs+=("${pkg##*/}")
	done

	/usr/bin/pacman "$@" || return $?
	[[ "$IS_CONTAINER" == true ]] && return 0
	pkg_shim_add pacman "${clean_pkgs[@]}"
}

_pacman_shim_remove() {
	local op="$1"
	if [[ "$op" != *n* || "$op" != *s* ]]; then
		echo "ERROR: pacman shim: use -Rns for clean removal (got: $op)" >&2
		return 1
	fi
	pkg_shim_require_flags "$*" --noconfirm || return 1

	local -a pkgs=()
	for arg in "${@:2}"; do
		case "$arg" in
		-*) continue ;;
		*) pkgs+=("$arg") ;;
		esac
	done

	/usr/bin/pacman "$@" || return $?
	[[ "$IS_CONTAINER" == true ]] && return 0
	[[ ${#pkgs[@]} -gt 0 ]] && pkg_shim_remove pacman "${pkgs[@]}"
}

_pacman_shim_upgrade() {
	# pacman -U <urls/files> — install from file/URL
	pkg_shim_require_flags "$*" --noconfirm || return 1

	# Collect URLs/file paths (non-flag positional args)
	local -a targets=()
	for arg in "${@:2}"; do
		case "$arg" in
		-*) continue ;;
		*) targets+=("$arg") ;;
		esac
	done

	# Download to temp dir, query each package name, record it
	local tmpdir
	tmpdir=$(mktemp -d)
	local -a pkg_names=()
	for target in "${targets[@]}"; do
		local file
		if [[ "$target" == http*://* ]]; then
			file="${tmpdir}/$(basename "$target")"
			curl -sL -o "$file" "$target"
		else
			file="$target"
		fi
		local name
		name=$(/usr/bin/pacman -Qip "$file" 2>/dev/null | sed -n 's/^Name *: *//p')
		if [[ -n "$name" ]]; then
			pkg_names+=("$name")
		fi
	done
	rm -rf "$tmpdir"

	/usr/bin/pacman "$@" || return $?
	[[ "$IS_CONTAINER" == true ]] && return 0
	[[ ${#pkg_names[@]} -gt 0 ]] && pkg_shim_add pacman "${pkg_names[@]}"
}

# Paru (AUR helper) shim — always paired with pacman
source "$(dirname "${BASH_SOURCE[0]}")/paru.sh"
