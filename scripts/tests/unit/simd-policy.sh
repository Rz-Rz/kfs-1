#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_simd_policy.rs"
SOURCE_MACHINE="src/kernel/machine/cpu.rs"
SOURCE_POLICY="src/kernel/klib/simd.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
host-simd-cpuid-absence-disables-support
host-simd-feature-bits-map-correctly
host-simd-uninitialized-policy-denies-acceleration
host-simd-runtime-blocked-policy-denies-acceleration
host-simd-runtime-owned-policy-is-observable
host-simd-runtime-owned-sse2-policy-allows-acceleration
host-simd-forced-scalar-policy-denies-acceleration
host-simd-no-cpuid-policy-denies-acceleration
host-simd-no-supported-features-stays-scalar
host-simd-guardrails-reach-klib
machine-defines-simd-support
klib-defines-runtime-policy
klib-policy-defaults-to-scalar-guardrails
memory-facade-exposes-simd-guardrails
EOF
}

describe_case() {
	case "$1" in
	host-simd-cpuid-absence-disables-support) printf '%s\n' "host SIMD support helper treats missing CPUID as no support" ;;
	host-simd-feature-bits-map-correctly) printf '%s\n' "host SIMD support helper maps MMX/SSE/SSE2 bits correctly" ;;
	host-simd-uninitialized-policy-denies-acceleration) printf '%s\n' "uninitialized SIMD policy denies all acceleration" ;;
	host-simd-runtime-blocked-policy-denies-acceleration) printf '%s\n' "runtime-blocked SIMD policy preserves detection but denies execution" ;;
	host-simd-runtime-owned-policy-is-observable) printf '%s\n' "runtime-owned SIMD policy is observable while acceleration remains deferred" ;;
	host-simd-runtime-owned-sse2-policy-allows-acceleration) printf '%s\n' "runtime-owned SIMD policy can allow SSE2 acceleration while MMX/SSE remain blocked" ;;
	host-simd-forced-scalar-policy-denies-acceleration) printf '%s\n' "forced-scalar SIMD policy denies all acceleration" ;;
	host-simd-no-cpuid-policy-denies-acceleration) printf '%s\n' "no-CPUID SIMD policy denies all acceleration" ;;
	host-simd-no-supported-features-stays-scalar) printf '%s\n' "CPUID-without-MMX/SSE/SSE2 still yields scalar-only policy" ;;
	host-simd-guardrails-reach-klib) printf '%s\n' "memory facade exposes the SIMD guardrail seam through klib" ;;
	machine-defines-simd-support) printf '%s\n' "machine layer defines SIMD detection helpers" ;;
	klib-defines-runtime-policy) printf '%s\n' "klib layer defines the runtime SIMD policy surface" ;;
	klib-policy-defaults-to-scalar-guardrails) printf '%s\n' "klib runtime policy defaults to scalar guardrails" ;;
	memory-facade-exposes-simd-guardrails) printf '%s\n' "memory facade exposes SIMD guardrail queries without importing machine" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${SOURCE_MACHINE}" ]] || die "missing machine SIMD source: ${SOURCE_MACHINE}"
	[[ -r "${SOURCE_POLICY}" ]] || die "missing klib SIMD policy source: ${SOURCE_POLICY}"
}

find_pattern() {
	local pattern="$1"
	shift

	if command -v rg >/dev/null 2>&1; then
		rg -n "${pattern}" -S "$@" >/dev/null
	else
		grep -En "${pattern}" "$@" >/dev/null
	fi
}

assert_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2

	if ! find_pattern "${pattern}" "$@"; then
		echo "FAIL src: missing ${label}"
		return 1
	fi

	echo "PASS src: ${label}"
}

run_host_tests() {
	local filter="$1"
	local test_bin="build/ut_simd_policy_${filter%_}"

	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-simd-cpuid-absence-disables-support)
		run_host_tests 'cpuid_absence_forces_no_simd_support'
		;;
	host-simd-feature-bits-map-correctly)
		run_host_tests 'cpuid_feature_bits_map_to_mmx_sse_and_sse2'
		;;
	host-simd-uninitialized-policy-denies-acceleration)
		run_host_tests 'uninitialized_policy_denies_all_acceleration'
		;;
	host-simd-runtime-blocked-policy-denies-acceleration)
		run_host_tests 'runtime_blocked_policy_preserves_detected_support_but_denies_execution'
		;;
	host-simd-runtime-owned-policy-is-observable)
		run_host_tests 'runtime_owned_policy_is_observable_but_still_scalar_only'
		;;
	host-simd-runtime-owned-sse2-policy-allows-acceleration)
		run_host_tests 'runtime_owned_sse2_policy_can_enable_acceleration'
		;;
	host-simd-forced-scalar-policy-denies-acceleration)
		run_host_tests 'forced_scalar_policy_denies_all_acceleration'
		;;
	host-simd-no-cpuid-policy-denies-acceleration)
		run_host_tests 'no_cpuid_policy_denies_all_acceleration'
		;;
	host-simd-no-supported-features-stays-scalar)
		run_host_tests 'no_supported_features_still_counts_as_scalar_policy'
		;;
	host-simd-guardrails-reach-klib)
		run_host_tests 'guardrails_reach_klib_without_arch_shortcuts'
		;;
	machine-defines-simd-support)
		assert_pattern '\bstruct[[:space:]]+SimdDetection\b' 'SimdDetection definition' "${SOURCE_MACHINE}"
		assert_pattern '\bfn[[:space:]]+detect_simd\b' 'detect_simd function' "${SOURCE_MACHINE}"
		assert_pattern '\bfxsr\b' 'FXSR capability bit tracking' "${SOURCE_MACHINE}"
		;;
	klib-defines-runtime-policy)
		assert_pattern '\bstruct[[:space:]]+RuntimePolicy\b' 'RuntimePolicy definition' "${SOURCE_POLICY}"
		assert_pattern '\bfn[[:space:]]+install_runtime_policy\b' 'runtime policy installation function' "${SOURCE_POLICY}"
		assert_pattern '\bstruct[[:space:]]+RuntimeStateSummary\b' 'runtime state summary type' "${SOURCE_POLICY}"
		;;
	klib-policy-defaults-to-scalar-guardrails)
		assert_pattern 'ScalarBlockReason::Uninitialized' 'uninitialized scalar guard reason' "${SOURCE_POLICY}"
		assert_pattern 'ScalarBlockReason::AccelerationDeferred' 'runtime-owned deferred scalar guard reason' "${SOURCE_POLICY}"
		assert_pattern 'ScalarBlockReason::AccelerationEnabled' 'runtime-owned acceleration-enabled reason' "${SOURCE_POLICY}"
		assert_pattern 'SimdExecutionMode::AccelerationEnabled' 'acceleration-enabled execution mode' "${SOURCE_POLICY}"
		assert_pattern '\bfn[[:space:]]+mmx_allowed\b' 'MMX guard query' "${SOURCE_POLICY}"
		assert_pattern '\bfn[[:space:]]+sse_allowed\b' 'SSE guard query' "${SOURCE_POLICY}"
		assert_pattern '\bfn[[:space:]]+sse2_allowed\b' 'SSE2 guard query' "${SOURCE_POLICY}"
		assert_pattern '\bfn[[:space:]]+ready\b' 'runtime-ready feature query' "${SOURCE_POLICY}"
		;;
	memory-facade-exposes-simd-guardrails)
		assert_pattern '\bfn[[:space:]]+simd_policy\b' 'memory SIMD policy query' 'src/kernel/klib/memory/mod.rs'
		assert_pattern '\bfn[[:space:]]+simd_mode\b' 'memory SIMD mode query' 'src/kernel/klib/memory/mod.rs'
		assert_pattern '\bfn[[:space:]]+simd_acceleration_allowed\b' 'memory SIMD guard query' 'src/kernel/klib/memory/mod.rs'
		;;
	*)
		die "usage: $0 <arch> {host-simd-cpuid-absence-disables-support|host-simd-feature-bits-map-correctly|host-simd-uninitialized-policy-denies-acceleration|host-simd-runtime-blocked-policy-denies-acceleration|host-simd-runtime-owned-policy-is-observable|host-simd-runtime-owned-sse2-policy-allows-acceleration|host-simd-forced-scalar-policy-denies-acceleration|host-simd-no-cpuid-policy-denies-acceleration|host-simd-no-supported-features-stays-scalar|host-simd-guardrails-reach-klib|machine-defines-simd-support|klib-defines-runtime-policy|klib-policy-defaults-to-scalar-guardrails|memory-facade-exposes-simd-guardrails}"
		;;
	esac
}

main() {
	if [[ "${1:-}" == "--list" ]] || [[ "${2:-}" == "--list" ]]; then
		list_cases
		exit 0
	fi

	if [[ "${1:-}" == "--description" ]]; then
		[[ -n "${2:-}" ]] || die "usage: $0 --description <case>"
		describe_case "${2}"
		exit 0
	fi

	if [[ "${2:-}" == "--description" ]]; then
		[[ -n "${3:-}" ]] || die "usage: $0 <arch> --description <case>"
		describe_case "${3}"
		exit 0
	fi

	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
	run_direct_case
}

main "$@"
