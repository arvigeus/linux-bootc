#!/usr/bin/env bash
## File-writing helpers — wraps the touch-sandwich pattern
##
## Usage:
##   fs_write /etc/foo.conf << 'EOF'
##   content here
##   EOF
##
##   fs_append /etc/foo.conf << 'EOF'
##   more content
##   EOF
##
##   fs_create /etc/foo.conf
##
## fs_write: creates parent directories, then touch → write → touch.
## fs_append: appends stdin, then touch to record the new final state.
## fs_create: ensures parent dirs and an empty file exist (idempotent).
##            Use before unshimmed writers (sed -i, shell redirects, or
##            commands like crudini that need the file to exist).
## All three rely on the shimmed `touch` from shims/fs.sh for tracking.

# Write stdin to file. Creates parent dirs. Tracks via touch-sandwich.
fs_write() {
	local file="$1"
	mkdir -p "$(dirname "$file")"
	touch "$file"
	cat >"$file"
	touch "$file"
}

# Append stdin to file and record final state.
fs_append() {
	local file="$1"
	cat >>"$file"
	touch "$file"
}

# Ensure parent dirs and file exist. Records the pre-modification state
# via the fs shim so the original is backed up before a later writer
# changes it.
fs_create() {
	local file="$1"
	mkdir -p "$(dirname "$file")"
	touch "$file"
}
