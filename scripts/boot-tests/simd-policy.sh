#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
# shellcheck disable=SC2034
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
LOG="build/m5-simd-policy-${CASE}.log"

list_cases() {
	cat <<'EOF'
phase4-runtime-acceleration-markers
phase4-runtime-acceleration-order
phase4-no-cpuid-stays-scalar
phase4-forced-disable-stays-scalar
EOF
}

describe_case() {
	case "$1" in
	phase4-runtime-acceleration-markers) printf '%s\n' "runtime emits Phase 4 ownership markers and enables SSE2 acceleration on supported CPUs" ;;
	phase4-runtime-acceleration-order) printf '%s\n' "runtime owns SIMD state and enables acceleration before helper self-check markers run" ;;
	phase4-no-cpuid-stays-scalar) printf '%s\n' "runtime falls back to scalar-only policy when CPUID is forced unavailable" ;;
	phase4-forced-disable-stays-scalar) printf '%s\n' "runtime stays scalar-only and does not own state when SIMD policy is forced off" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

iso_path() {
	case "${CASE}" in
	phase4-no-cpuid-stays-scalar)
		printf 'build/os-%s-test-no-cpuid.iso\n' "${ARCH}"
		;;
	phase4-forced-disable-stays-scalar)
		printf 'build/os-%s-test-disable-simd.iso\n' "${ARCH}"
		;;
	*)
		printf 'build/os-%s-test.iso\n' "${ARCH}"
		;;
	esac
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
	local token
	local line

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
	phase4-runtime-acceleration-markers)
		assert_log_contains "SIMD_POLICY_OK"
		assert_log_contains "SIMD_MODE_ACCELERATION_ENABLED"
		assert_log_contains "SIMD_CPUID_PRESENT"
		assert_log_contains "SIMD_FXSR_OK"
		assert_log_contains "SIMD_RUNTIME_OWNED"
		assert_log_contains "SIMD_X87_INIT_OK"
		assert_log_contains "SIMD_MXCSR_DEFAULT_OK"
		assert_log_contains "SIMD_POLICY_ACCELERATION_ENABLED"
		assert_log_contains "SIMD_SSE2_OK"
		;;
	phase4-runtime-acceleration-order)
		assert_log_order "LAYOUT_OK" "SIMD_POLICY_OK" "SIMD_RUNTIME_OWNED" "SIMD_POLICY_ACCELERATION_ENABLED" "STRING_HELPERS_OK"
		;;
	phase4-no-cpuid-stays-scalar)
		assert_log_contains "SIMD_POLICY_OK"
		assert_log_contains "SIMD_MODE_SCALAR_ONLY"
		assert_log_contains "SIMD_CPUID_ABSENT"
		assert_log_contains "SIMD_RUNTIME_NOT_OWNED"
		assert_log_contains "SIMD_POLICY_NO_CPUID"
		;;
	phase4-forced-disable-stays-scalar)
		assert_log_contains "SIMD_POLICY_OK"
		assert_log_contains "SIMD_MODE_SCALAR_ONLY"
		assert_log_contains "SIMD_CPUID_PRESENT"
		assert_log_contains "SIMD_RUNTIME_NOT_OWNED"
		assert_log_contains "SIMD_POLICY_FORCED_SCALAR"
		;;
	*)
		die "usage: $0 <arch> {phase4-runtime-acceleration-markers|phase4-runtime-acceleration-order|phase4-no-cpuid-stays-scalar|phase4-forced-disable-stays-scalar}"
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
