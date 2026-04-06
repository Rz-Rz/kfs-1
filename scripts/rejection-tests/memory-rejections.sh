#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
# shellcheck disable=SC2034
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
FAIL_RC="${TEST_FAIL_RC:-35}"
LOG="build/m5-memory-negative-${CASE}.log"

list_cases() {
	cat <<'EOF'
bad-memory-self-check-fails
bad-memory-stops-before-normal-flow
EOF
}

describe_case() {
	case "$1" in
	bad-memory-self-check-fails) printf '%s\n' "rejects a broken memory-helper self-check at runtime" ;;
	bad-memory-stops-before-normal-flow) printf '%s\n' "memory-helper failure stops before normal flow resumes" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

iso_path() {
	printf 'build/os-%s-test-bad-memory.iso\n' "${ARCH}"
}

run_qemu_capture() {
	local iso
	iso="$(iso_path)"
	[[ -r "${iso}" ]] || die "missing ISO: ${iso} (build it with make test-artifacts arch=${ARCH})"

	set +e
	timeout --foreground "${TIMEOUT_SECS}" \
		qemu-system-i386 \
		-cdrom "${iso}" \
		-device isa-debug-exit,iobase=0xf4,iosize=0x04 \
		-serial stdio \
		-display none \
		-monitor none \
		-no-reboot \
		-no-shutdown \
		</dev/null >"${LOG}" 2>&1
	local rc="$?"
	set -e

	if [[ "${rc}" -ne "${FAIL_RC}" ]]; then
		echo "FAIL ${CASE}: expected FAIL rc=${FAIL_RC}, got rc=${rc}" >&2
		cat "${LOG}" >&2
		exit 1
	fi
}

assert_log_contains() {
	local token="$1"
	if ! grep -qFx "${token}" "${LOG}"; then
		echo "FAIL ${CASE}: missing runtime marker ${token}" >&2
		cat "${LOG}" >&2
		exit 1
	fi
}

assert_log_not_contains() {
	local token="$1"
	if grep -qFx "${token}" "${LOG}"; then
		echo "FAIL ${CASE}: unexpected runtime marker ${token}" >&2
		cat "${LOG}" >&2
		exit 1
	fi
}

run_direct_case() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	run_qemu_capture

	case "${CASE}" in
	bad-memory-self-check-fails)
		assert_log_contains "KMAIN_OK"
		assert_log_contains "BSS_OK"
		assert_log_contains "LAYOUT_OK"
		assert_log_contains "STRING_HELPERS_OK"
		assert_log_contains "MEMORY_HELPERS_FAIL"
		;;
	bad-memory-stops-before-normal-flow)
		assert_log_contains "MEMORY_HELPERS_FAIL"
		assert_log_not_contains "MEMCPY_OK"
		assert_log_not_contains "MEMSET_OK"
		assert_log_not_contains "MEMORY_HELPERS_OK"
		assert_log_not_contains "EARLY_INIT_OK"
		assert_log_not_contains "KMAIN_FLOW_OK"
		;;
	*)
		die "usage: $0 <arch> {bad-memory-self-check-fails|bad-memory-stops-before-normal-flow}"
		;;
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

	run_direct_case
}

main "$@"
