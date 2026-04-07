#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
	cat <<'EOF'
bss-before-kernel
bss-end-before-bss-start
kernel-end-before-bss-end
EOF
}

describe_case() {
	case "$1" in
	bss-before-kernel) printf '%s\n' 'rejects bss_start before kernel_start' ;;
	bss-end-before-bss-start) printf '%s\n' 'rejects bss_end before bss_start' ;;
	kernel-end-before-bss-end) printf '%s\n' 'rejects kernel_end before bss_end' ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

run_direct_case() {
	local stamp="build/rejections/layout-${ARCH}-${CASE}.stamp"
	[[ -r "${stamp}" ]] || die "missing rejection proof: ${stamp} (build it with make test-artifacts arch=${ARCH})"
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

	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

	run_direct_case
}

main "$@"
