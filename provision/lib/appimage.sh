#!/usr/bin/env bash
## AppImage helpers

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
	local temp="/tmp/${filename}"

	curl -L -o "$temp" "$url"
	chmod +x "$temp"

	gearlever --integrate --yes "$temp" \
		"--url=${url}" "--repo=${repo}" "--pattern=${pattern}"

	rm -f "$temp"
}
