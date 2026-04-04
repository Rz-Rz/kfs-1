#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="${KFS_BUILD_LOCK_FILE:-.git/kfs-build.lock}"

if [[ "$#" -eq 0 ]]; then
	echo "error: usage: $0 <command> [args...]" >&2
	exit 2
fi

mkdir -p "$(dirname "${LOCK_FILE}")"
exec 9>"${LOCK_FILE}"
flock 9
"$@"
