#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "error: $*" >&2
	exit 1
}

if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
	[[ "${SOURCE_DATE_EPOCH}" =~ ^[0-9]+$ ]] || die "SOURCE_DATE_EPOCH must be an integer UNIX timestamp"
	printf '%s\n' "${SOURCE_DATE_EPOCH}"
	exit 0
fi

command -v git >/dev/null 2>&1 || die "SOURCE_DATE_EPOCH is unset and git is unavailable"

epoch="$(git log -1 --format=%ct -- . 2>/dev/null || true)"
[[ -n "${epoch}" ]] || die "failed to derive SOURCE_DATE_EPOCH from git history"
[[ "${epoch}" =~ ^[0-9]+$ ]] || die "git returned a non-integer SOURCE_DATE_EPOCH"

printf '%s\n' "${epoch}"
