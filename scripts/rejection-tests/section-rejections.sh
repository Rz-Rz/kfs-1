#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
	cat <<'EOF'
text-missing
text-wrong-type
rodata-missing
rodata-wrong-type
data-missing
data-wrong-type
bss-missing
bss-wrong-type
EOF
}

describe_case() {
	case "$1" in
	text-missing) printf '%s\n' "rejects missing .text section" ;;
	text-wrong-type) printf '%s\n' "rejects .text with wrong section type" ;;
	rodata-missing) printf '%s\n' "rejects missing .rodata section" ;;
	rodata-wrong-type) printf '%s\n' "rejects .rodata with wrong section type" ;;
	data-missing) printf '%s\n' "rejects missing .data section" ;;
	data-wrong-type) printf '%s\n' "rejects .data with wrong section type" ;;
	bss-missing) printf '%s\n' "rejects missing .bss section" ;;
	bss-wrong-type) printf '%s\n' "rejects .bss with wrong section type" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

run_direct_case() {
	local stamp="build/rejections/section-${ARCH}-${CASE}.stamp"
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
