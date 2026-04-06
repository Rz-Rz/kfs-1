#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-release-boot-calls-kmain}"

list_cases() {
	cat <<'EOF'
release-boot-calls-kmain
EOF
}

describe_case() {
	case "$1" in
	release-boot-calls-kmain) printf '%s\n' "release boot code calls kmain" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_kmain_callsite() {
	local kernel="$1"
	[[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make all/iso arch=${ARCH})"

	if ! objdump -d "${kernel}" | sed -n '/<start>:/,/^$/p' | grep -qE 'call[[:space:]]+.*<kmain>'; then
		echo "FAIL ${kernel}: start block does not call kmain"
		objdump -d "${kernel}" | sed -n '/<start>:/,/^$/p' >&2 || true
		return 1
	fi
}

run_direct() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	[[ "${CASE}" == "release-boot-calls-kmain" ]] || die "unknown case: ${CASE}"
	assert_kmain_callsite "build/kernel-${ARCH}.bin"
}

run_host_case() {
	bash scripts/with-build-lock.sh \
		bash scripts/container.sh run -- \
		bash -lc "make -B all arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/release-kmain-callsite.sh '${ARCH}' '${CASE}'"
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

	if describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
		run_host_case
		return 0
	fi

	run_direct
}

main "$@"
