#!/usr/bin/env bash
## GitHub helper functions

# Get the latest release tag for a GitHub repo.
# Usage: github_latest_tag <owner/repo>
github_latest_tag() {
    curl -sI "https://github.com/$1/releases/latest" | grep -i ^location | sed 's|.*/||;s|\r||'
}

# Get the download URL for an asset from the latest GitHub release.
# Usage: github_latest_download <owner/repo> <filename-pattern>
# The pattern is matched against asset filenames (grep -E).
# Returns the first matching browser_download_url.
github_latest_download() {
    local repo="$1" pattern="$2"
    curl -s "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -o '"browser_download_url": "[^"]*"' \
        | cut -d'"' -f4 \
        | grep -E "$pattern" \
        | head -n 1
}
