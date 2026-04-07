#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-release-kernel-exports-kmain}"
# shellcheck disable=SC2034
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

list_cases() {
	cat <<'EOF'
release-kernel-exports-kmain
EOF
}

describe_case() {
	case "$1" in
	release-kernel-exports-kmain) printf '%s\n' "release kernel exports kmain" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_kmain_symbol() {
	local kernel="$1"
	local symbol_table
	[[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make all/iso arch=${ARCH})"
	symbol_table="$(nm -n "${kernel}")"

	if ! awk '$2 == "T" && $3 == "kmain" { found = 1 } END { exit(found ? 0 : 1) }' <<<"${symbol_table}"; then
		echo "FAIL ${kernel}: missing Rust entry symbol (expected: T kmain)"
		grep -E '\bkmain\b' <<<"${symbol_table}" || true
		return 1
	fi
}

run_direct() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	[[ "${CASE}" == "release-kernel-exports-kmain" ]] || die "unknown case: ${CASE}"
	assert_kmain_symbol "build/kernel-${ARCH}.bin"
}

main() {
	if [[ "${ARCH}" == "--list" ]]; then
		list_cases
		return 0
	fi

	if [[ "${ARCH}" == "--description" ]]; then
		describe_case "${CASE}"
		return 0
	fi

	run_direct
}

main "$@"
