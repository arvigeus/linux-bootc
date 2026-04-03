#!/usr/bin/env bash
## AppImage helpers

# Derive a stable app ID from an AppImage filename.
# Strips version, architecture, and .AppImage suffix.
appimage_app_id() {
	basename "$1" | sed 's/[-_][0-9].*//; s/\.AppImage$//i' | tr '[:upper:]' '[:lower:]'
}

# Download an AppImage from GitHub and integrate via gearlever.
# Usage: appimage_install_github <owner/repo> <asset-pattern>
# Example: appimage_install_github "<org>/<repo>" "x86_64.AppImage"
appimage_install_github() {
	local repo="$1" pattern="$2"

	local url
	url=$(github_latest_download "$repo" "$pattern")
	if [[ -z "$url" ]]; then
		echo "ERROR: No AppImage matching '${pattern}' found in ${repo}" >&2
		return 1
	fi

	local filename
	filename=$(basename "$url")

	if [[ "$IS_CONTAINER" != true ]]; then
		local app_id
		app_id=$(appimage_app_id "$filename")
		gearlever --list-installed 2>/dev/null | grep -qi "$app_id" && return 0
	fi

	local temp="/tmp/${filename}"

	curl -L -o "$temp" "$url"
	chmod +x "$temp"

	gearlever --integrate --yes "$temp" \
		"--url=${url}" "--repo=${repo}" "--pattern=${pattern}"

	rm -f "$temp"
}
