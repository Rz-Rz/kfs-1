#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
	cat <<'EOF'
build-test-iso
build-test-img-artifact
EOF
}

describe_case() {
	case "$1" in
	build-test-iso) printf '%s\n' "build the generated test ISO artifact" ;;
	build-test-img-artifact) printf '%s\n' "build the generated test IMG artifact" ;;
	*) return 1 ;;
	esac
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

	case "${CASE}" in
	build-test-iso)
		test -r "build/os-${ARCH}-test.iso"
		;;
	build-test-img-artifact)
		test -r "build/os-${ARCH}-test.img"
		;;
	*)
		echo "error: usage: $0 <arch> {build-test-iso|build-test-img-artifact}" >&2
		exit 2
		;;
	esac
}

main "$@"
