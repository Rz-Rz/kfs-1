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
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make -B iso-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL:-0}' >/dev/null"
		;;
	build-test-img-artifact)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make -B img-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL:-0}' >/dev/null"
		;;
	*)
		echo "error: usage: $0 <arch> {build-test-iso|build-test-img-artifact}" >&2
		exit 2
		;;
	esac
}

main "$@"
