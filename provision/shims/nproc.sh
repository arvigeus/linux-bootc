#!/usr/bin/env bash
## nproc shim — override CPU count during container builds
##
## During bootc container builds, nproc reports the build machine's CPU count,
## not the target machine's. Set CPU_CORES in .env to provide the correct value.
##
## In bootstrap mode the real nproc is always used (the machine is the target).

nproc() {
	if [[ "$IS_CONTAINER" == true ]] && [[ -n "${CPU_CORES:-}" ]]; then
		echo "$CPU_CORES"
	else
		/usr/bin/nproc "$@"
	fi
}
