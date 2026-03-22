#!/usr/bin/env bash
## GitHub helper functions

github_latest_tag() {
    curl -sI "https://github.com/$1/releases/latest" | grep -i ^location | sed 's|.*/||;s|\r||'
}
