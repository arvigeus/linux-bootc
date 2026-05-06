#!/usr/bin/env bash
## Repository health checks for GitHub and GitLab.
##
## repo_health <spec> [-m <months>] [--quit]
##   <spec> is one of:
##     github:<owner>/<repo>
##     gitlab:<owner>/<repo>
##     https://github.com/<owner>/<repo>
##     https://gitlab.com/<owner>/<repo>
##
##   Warns to stderr if the repo is archived or not found. With -m <months>,
##   also warns if there has been no code push in that many months. With
##   --quit, returns non-zero when any warning fires (so a build under
##   `set -e` halts). API transport failures (network, rate limit,
##   unexpected status) print a debug line and return 0 regardless.
##
##   "Activity" is code-only on both hosts: GitHub `pushed_at`, GitLab
##   latest commit on the default branch. Issue/MR comments do not count.

# Fetch URL into $_rh_body / $_rh_code (declare both `local` in the caller).
# Returns 0 on transport success, 1 on transport failure.
_repo_fetch() {
	local raw
	raw=$(curl -sL -w $'\n%{http_code}' "$1") || return 1
	_rh_code="${raw##*$'\n'}"
	_rh_body="${raw%$'\n'*}"
}

repo_health() {
	local spec="$1"
	[[ -n "$spec" ]] || {
		echo "missing spec" >&2
		return 2
	}
	shift

	local months=0 quit=0
	while (($# > 0)); do
		case "$1" in
		-m)
			months="$2"
			shift 2
			;;
		--quit)
			quit=1
			shift
			;;
		*)
			echo "unknown option: $1" >&2
			return 2
			;;
		esac
	done

	local host path
	case "$spec" in
	github:*)
		host=github
		path="${spec#github:}"
		;;
	gitlab:*)
		host=gitlab
		path="${spec#gitlab:}"
		;;
	https://github.com/*)
		host=github
		path="${spec#https://github.com/}"
		;;
	https://gitlab.com/*)
		host=gitlab
		path="${spec#https://gitlab.com/}"
		;;
	*)
		echo "unrecognized spec: $spec" >&2
		return 2
		;;
	esac
	path="${path%.git}"
	path="${path%/}"

	local project_url
	case "$host" in
	github) project_url="https://api.github.com/repos/${path}" ;;
	gitlab) project_url="https://gitlab.com/api/v4/projects/${path//\//%2F}" ;;
	esac

	local _rh_body _rh_code
	if ! _repo_fetch "$project_url"; then
		echo "[WARNING] could not query ${host} for ${path}" >&2
		return 0
	fi
	case "$_rh_code" in
	200) ;;
	404)
		echo "[WARNING] ${spec} not found" >&2
		((quit)) && return 1
		return 0
		;;
	*)
		echo "[DEBUG] ${host} returned HTTP ${_rh_code} for ${path}" >&2
		return 0
		;;
	esac

	local archived
	archived=$(echo "$_rh_body" | grep -oE '"archived"[[:space:]]*:[[:space:]]*(true|false)' | head -1 | grep -oE '(true|false)$')
	if [[ "$archived" == "true" ]]; then
		echo "[WARNING] ${spec} is archived" >&2
		((quit)) && return 1
	fi

	if ((months > 0)); then
		local activity=""
		case "$host" in
		github)
			activity=$(echo "$_rh_body" | grep -o '"pushed_at"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
			;;
		gitlab)
			if _repo_fetch "https://gitlab.com/api/v4/projects/${path//\//%2F}/repository/commits?per_page=1" && [[ "$_rh_code" == "200" ]]; then
				activity=$(echo "$_rh_body" | grep -o '"committed_date"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
			fi
			;;
		esac

		if [[ -n "$activity" ]]; then
			local last_ts now_ts diff_months
			if last_ts=$(date -d "$activity" +%s 2>/dev/null); then
				now_ts=$(date +%s)
				diff_months=$(((now_ts - last_ts) / 2629800))
				if ((diff_months > months)); then
					echo "[WARNING] ${spec} has had no activity for ${diff_months} months" >&2
					((quit)) && return 1
				fi
			fi
		fi
	fi

	return 0
}
