#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
# shellcheck disable=SC2034
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
LOG="build/m5-memory-runtime-${CASE}.log"
INIT_SOURCE="src/kernel/core/init.rs"

iso_path() {
	case "${CASE}" in
	runtime-confirms-memcpy-scalar-fallback-when-no-cpuid | runtime-confirms-memset-scalar-fallback-when-no-cpuid)
		printf 'build/os-%s-test-no-cpuid.iso\n' "${ARCH}"
		;;
	runtime-confirms-memcpy-scalar-fallback-when-simd-disabled | runtime-confirms-memset-scalar-fallback-when-simd-disabled)
		printf 'build/os-%s-test-disable-simd.iso\n' "${ARCH}"
		;;
	*)
		printf 'build/os-%s-test.iso\n' "${ARCH}"
		;;
	esac
}

list_cases() {
	cat <<'EOF'
release-core-init-calls-memory-memcpy
runtime-confirms-memcpy
runtime-confirms-memcpy-backend-sse2
runtime-confirms-memcpy-scalar-fallback-when-no-cpuid
runtime-confirms-memcpy-scalar-fallback-when-simd-disabled
release-core-init-calls-memory-memset
runtime-confirms-memset
runtime-confirms-memset-backend-sse2
runtime-confirms-memset-scalar-fallback-when-no-cpuid
runtime-confirms-memset-scalar-fallback-when-simd-disabled
runtime-confirms-memory-helpers
runtime-memory-acceleration-happens-after-simd-runtime-ownership
runtime-memory-backend-markers-are-ordered
runtime-memory-markers-are-ordered
EOF
}

describe_case() {
	case "$1" in
	release-core-init-calls-memory-memcpy) printf '%s\n' "release core init calls memory::memcpy in the memory sanity path" ;;
	runtime-confirms-memcpy) printf '%s\n' "runtime emits MEMCPY_OK" ;;
	runtime-confirms-memcpy-backend-sse2) printf '%s\n' "runtime emits MEMCPY_BACKEND_SSE2 when the default CPU supports SSE2" ;;
	runtime-confirms-memcpy-scalar-fallback-when-no-cpuid) printf '%s\n' "runtime falls back to MEMCPY_BACKEND_SCALAR when CPUID is forced unavailable" ;;
	runtime-confirms-memcpy-scalar-fallback-when-simd-disabled) printf '%s\n' "runtime falls back to MEMCPY_BACKEND_SCALAR when SIMD is forced off" ;;
	release-core-init-calls-memory-memset) printf '%s\n' "release core init calls memory::memset in the memory sanity path" ;;
	runtime-confirms-memset) printf '%s\n' "runtime emits MEMSET_OK" ;;
	runtime-confirms-memset-backend-sse2) printf '%s\n' "runtime emits MEMSET_BACKEND_SSE2 when the default CPU supports SSE2" ;;
	runtime-confirms-memset-scalar-fallback-when-no-cpuid) printf '%s\n' "runtime falls back to MEMSET_BACKEND_SCALAR when CPUID is forced unavailable" ;;
	runtime-confirms-memset-scalar-fallback-when-simd-disabled) printf '%s\n' "runtime falls back to MEMSET_BACKEND_SCALAR when SIMD is forced off" ;;
	runtime-confirms-memory-helpers) printf '%s\n' "runtime emits MEMORY_HELPERS_OK" ;;
	runtime-memory-acceleration-happens-after-simd-runtime-ownership) printf '%s\n' "runtime reaches SIMD ownership before selecting SSE2 memory backends" ;;
	runtime-memory-backend-markers-are-ordered) printf '%s\n' "runtime emits backend markers before helper success markers" ;;
	runtime-memory-markers-are-ordered) printf '%s\n' "runtime emits MEMCPY_OK then MEMSET_OK then MEMORY_HELPERS_OK in order" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
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
	return 0
}

assert_pattern_absent() {
	local pattern="$1"
	local label="$2"
	shift 2

	if find_pattern "${pattern}" "$@"; then
		echo "FAIL src: unexpected ${label}"
		return 1
	fi

	echo "PASS src: ${label} absent"
	return 0
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
	release-core-init-calls-memory-memcpy)
		assert_pattern 'memory::memcpy\(' 'memory::memcpy call in core init' "${INIT_SOURCE}"
		assert_pattern_absent '\bkfs_memcpy\(' 'kfs_memcpy call in core init' "${INIT_SOURCE}"
		assert_log_contains "MEMCPY_OK"
		;;
	runtime-confirms-memcpy)
		assert_log_contains "MEMCPY_OK"
		;;
	runtime-confirms-memcpy-backend-sse2)
		assert_log_contains "MEMCPY_BACKEND_SSE2"
		;;
	runtime-confirms-memcpy-scalar-fallback-when-no-cpuid)
		assert_log_contains "MEMCPY_BACKEND_SCALAR"
		;;
	runtime-confirms-memcpy-scalar-fallback-when-simd-disabled)
		assert_log_contains "MEMCPY_BACKEND_SCALAR"
		;;
	release-core-init-calls-memory-memset)
		assert_pattern 'memory::memset\(' 'memory::memset call in core init' "${INIT_SOURCE}"
		assert_pattern_absent '\bkfs_memset\(' 'kfs_memset call in core init' "${INIT_SOURCE}"
		assert_log_contains "MEMSET_OK"
		;;
	runtime-confirms-memset)
		assert_log_contains "MEMSET_OK"
		;;
	runtime-confirms-memset-backend-sse2)
		assert_log_contains "MEMSET_BACKEND_SSE2"
		;;
	runtime-confirms-memset-scalar-fallback-when-no-cpuid)
		assert_log_contains "MEMSET_BACKEND_SCALAR"
		;;
	runtime-confirms-memset-scalar-fallback-when-simd-disabled)
		assert_log_contains "MEMSET_BACKEND_SCALAR"
		;;
	runtime-confirms-memory-helpers)
		assert_log_contains "MEMORY_HELPERS_OK"
		;;
	runtime-memory-acceleration-happens-after-simd-runtime-ownership)
		assert_log_order "SIMD_RUNTIME_OWNED" "MEMCPY_BACKEND_SSE2" "MEMSET_BACKEND_SSE2" "MEMORY_HELPERS_OK"
		;;
	runtime-memory-backend-markers-are-ordered)
		assert_log_order "MEMCPY_BACKEND_SSE2" "MEMCPY_OK" "MEMSET_BACKEND_SSE2" "MEMSET_OK" "MEMORY_HELPERS_OK"
		;;
	runtime-memory-markers-are-ordered)
		assert_log_order "MEMCPY_OK" "MEMSET_OK" "MEMORY_HELPERS_OK"
		;;
	*)
		die "usage: $0 <arch> {release-core-init-calls-memory-memcpy|runtime-confirms-memcpy|runtime-confirms-memcpy-backend-sse2|runtime-confirms-memcpy-scalar-fallback-when-no-cpuid|runtime-confirms-memcpy-scalar-fallback-when-simd-disabled|release-core-init-calls-memory-memset|runtime-confirms-memset|runtime-confirms-memset-backend-sse2|runtime-confirms-memset-scalar-fallback-when-no-cpuid|runtime-confirms-memset-scalar-fallback-when-simd-disabled|runtime-confirms-memory-helpers|runtime-memory-acceleration-happens-after-simd-runtime-ownership|runtime-memory-backend-markers-are-ordered|runtime-memory-markers-are-ordered}"
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
