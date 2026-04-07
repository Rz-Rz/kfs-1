#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-runtime-markers-are-ordered}"
# shellcheck disable=SC2034
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
LOG="build/m4-runtime-${CASE}.log"
source "$(dirname "${BASH_SOURCE[0]}")/lib/qemu-direct.bash"

list_cases() {
	cat <<'EOF'
runtime-reaches-kmain
runtime-confirms-bss-zero
runtime-confirms-layout
runtime-completes-early-init
runtime-markers-are-ordered
EOF
}

describe_case() {
	case "$1" in
	runtime-reaches-kmain) printf '%s\n' "runtime reaches Rust kmain" ;;
	runtime-confirms-bss-zero) printf '%s\n' "runtime confirms BSS starts at zero" ;;
	runtime-confirms-layout) printf '%s\n' "runtime confirms exported layout bounds" ;;
	runtime-completes-early-init) printf '%s\n' "runtime completes early init before normal flow" ;;
	runtime-markers-are-ordered) printf '%s\n' "runtime markers appear in the expected order" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

iso_path() {
	printf 'build/os-%s-test.iso\n' "${ARCH}"
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

	if [[ "${rc}" -ne "${PASS_RC}" ]]; then
		echo "FAIL ${CASE}: expected PASS rc=${PASS_RC}, got rc=${rc}" >&2
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

assert_log_order() {
	local previous_line=0
	local token line

	for token in "$@"; do
		line="$(grep -nFx "${token}" "${LOG}" | head -n 1 | cut -d: -f1)"
		[[ -n "${line}" ]] || {
			echo "FAIL ${CASE}: missing runtime marker ${token}" >&2
			cat "${LOG}" >&2
			exit 1
		}

		if ((line <= previous_line)); then
			echo "FAIL ${CASE}: runtime marker ${token} is out of order" >&2
			cat "${LOG}" >&2
			exit 1
		fi

		previous_line="${line}"
	done
}

run_direct_case() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	run_qemu_capture

	case "${CASE}" in
	runtime-reaches-kmain)
		assert_log_contains "KMAIN_OK"
		;;
	runtime-confirms-bss-zero)
		assert_log_contains "BSS_OK"
		;;
	runtime-confirms-layout)
		assert_log_contains "LAYOUT_OK"
		;;
	runtime-completes-early-init)
		assert_log_contains "EARLY_INIT_OK"
		;;
	runtime-markers-are-ordered)
		assert_log_order "KMAIN_OK" "BSS_OK" "LAYOUT_OK" "EARLY_INIT_OK" "KMAIN_FLOW_OK"
		;;
	*)
		die "usage: $0 <arch> {runtime-reaches-kmain|runtime-confirms-bss-zero|runtime-confirms-layout|runtime-completes-early-init|runtime-markers-are-ordered}"
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
