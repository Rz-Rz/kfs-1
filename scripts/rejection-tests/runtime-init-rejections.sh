#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
# shellcheck disable=SC2034
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
FAIL_RC="${TEST_FAIL_RC:-35}"
LOG="build/m4-runtime-negative-${CASE}.log"
source "$(dirname "${BASH_SOURCE[0]}")/../boot-tests/lib/qemu-direct.bash"

list_cases() {
	cat <<'EOF'
dirty-bss-canary-fails
dirty-bss-stops-before-layout
bad-layout-fails
bad-layout-stops-before-early-init
EOF
}

describe_case() {
	case "$1" in
	dirty-bss-canary-fails) printf '%s\n' "rejects a non-zero BSS canary at runtime" ;;
	dirty-bss-stops-before-layout) printf '%s\n' "dirty BSS failure stops before layout success" ;;
	bad-layout-fails) printf '%s\n' "rejects a bad runtime layout assumption" ;;
	bad-layout-stops-before-early-init) printf '%s\n' "layout failure stops before early-init success" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

iso_path() {
	case "${CASE}" in
	dirty-bss-canary-fails | dirty-bss-stops-before-layout)
		printf 'build/os-%s-test-dirty-bss.iso\n' "${ARCH}"
		;;
	bad-layout-fails | bad-layout-stops-before-early-init)
		printf 'build/os-%s-test-bad-layout.iso\n' "${ARCH}"
		;;
	*)
		die "unknown case: ${CASE}"
		;;
	esac
}

run_qemu_capture() {
	local iso
	local rc
	iso="$(iso_path)"
	[[ -r "${iso}" ]] || die "missing ISO: ${iso} (build it with make test-artifacts arch=${ARCH})"

	rc="$(
		qemu_direct_capture "${LOG}" "${TIMEOUT_SECS}" cdrom "${iso}" \
			-device isa-debug-exit,iobase=0xf4,iosize=0x04 \
			-serial stdio \
			-display none \
			-monitor none \
			-no-reboot \
			-no-shutdown
	)"

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
	dirty-bss-canary-fails)
		assert_log_contains "KMAIN_OK"
		assert_log_contains "BSS_FAIL"
		;;
	dirty-bss-stops-before-layout)
		assert_log_contains "BSS_FAIL"
		assert_log_not_contains "LAYOUT_OK"
		assert_log_not_contains "EARLY_INIT_OK"
		;;
	bad-layout-fails)
		assert_log_contains "KMAIN_OK"
		assert_log_contains "BSS_OK"
		assert_log_contains "LAYOUT_FAIL"
		;;
	bad-layout-stops-before-early-init)
		assert_log_contains "LAYOUT_FAIL"
		assert_log_not_contains "EARLY_INIT_OK"
		assert_log_not_contains "KMAIN_FLOW_OK"
		;;
	*)
		die "usage: $0 <arch> {dirty-bss-canary-fails|dirty-bss-stops-before-layout|bad-layout-fails|bad-layout-stops-before-early-init}"
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
