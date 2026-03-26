#!/usr/bin/env bash
## In containers: TODO
## On bare metal: runs the real flatpak command

gearlever() {
    [[ "$IS_CONTAINER" == true ]] && return 0
    /usr/bin/flatpak run it.mijorus.gearlever "$@"
}
