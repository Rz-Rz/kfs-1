#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
	cat <<'EOF'
interp-pt-interp-present
dynamic-section-present
unresolved-external-symbol
host-runtime-marker-strings
EOF
}

describe_case() {
	case "$1" in
	interp-pt-interp-present) printf '%s\n' "rejects forced .interp / PT_INTERP metadata" ;;
	dynamic-section-present) printf '%s\n' "rejects forced .dynamic metadata" ;;
	unresolved-external-symbol) printf '%s\n' "rejects an unresolved external symbol" ;;
	host-runtime-marker-strings) printf '%s\n' "rejects libc/dynamic-loader marker strings" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

run_direct_case() {
	local stamp="build/rejections/freestanding-${ARCH}-${CASE}.stamp"
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
	describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
	run_direct_case
}

main "$@"
