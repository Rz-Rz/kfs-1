#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_memory.rs"
SOURCE_CRATE="src/kernel/klib/memory/mod.rs"
SOURCE_IMPL="src/kernel/klib/memory/imp.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
host-memcpy-unit-tests-pass
host-memcpy-zero-length-behavior
host-memcpy-return-pointer-behavior
host-memcpy-same-pointer
host-memcpy-unaligned-pointers
host-memcpy-sentinel-bounds
host-memset-unit-tests-pass
host-memset-zero-byte-fill
host-memset-zero-length-behavior
host-memset-return-pointer-behavior
host-memset-sentinel-bounds
host-memory-backends-default-to-scalar
host-memory-backends-stay-scalar-when-runtime-owned
host-memory-backends-stay-scalar-when-runtime-blocked
host-memory-backends-choose-sse2-when-allowed
host-memcpy-sse2-backend-preserves-contract
host-memset-sse2-backend-preserves-contract
rust-defines-memcpy
rust-defines-memset
rust-defines-memory-backend-dispatch
memory-facade-exposes-backend-queries
rust-exports-kfs-memcpy
rust-exports-kfs-memset
rust-avoids-extern-memcpy
rust-avoids-extern-memset
release-kernel-exports-kfs-memcpy
release-kernel-exports-kfs-memset
memory-helpers-avoid-volatile-access
EOF
}

describe_case() {
	case "$1" in
	host-memcpy-unit-tests-pass) printf '%s\n' "host memcpy baseline unit tests pass" ;;
	host-memcpy-zero-length-behavior) printf '%s\n' "host memcpy zero-length behavior is correct" ;;
	host-memcpy-return-pointer-behavior) printf '%s\n' "host memcpy returns the original destination pointer" ;;
	host-memcpy-same-pointer) printf '%s\n' "host memcpy preserves data when source and destination pointers are identical" ;;
	host-memcpy-unaligned-pointers) printf '%s\n' "host memcpy handles unaligned ordinary-memory pointers" ;;
	host-memcpy-sentinel-bounds) printf '%s\n' "host memcpy preserves bytes outside the requested range" ;;
	host-memset-unit-tests-pass) printf '%s\n' "host memset baseline unit tests pass" ;;
	host-memset-zero-byte-fill) printf '%s\n' "host memset fills ordinary memory with the zero byte value" ;;
	host-memset-zero-length-behavior) printf '%s\n' "host memset zero-length behavior is correct" ;;
	host-memset-return-pointer-behavior) printf '%s\n' "host memset returns the original destination pointer" ;;
	host-memset-sentinel-bounds) printf '%s\n' "host memset preserves bytes outside the requested range" ;;
	host-memory-backends-default-to-scalar) printf '%s\n' "host memory backend selection defaults to scalar when policy is uninitialized" ;;
	host-memory-backends-stay-scalar-when-runtime-owned) printf '%s\n' "host memory backend selection stays scalar while acceleration is still deferred" ;;
	host-memory-backends-stay-scalar-when-runtime-blocked) printf '%s\n' "host memory backend selection stays scalar when runtime policy blocks acceleration" ;;
	host-memory-backends-choose-sse2-when-allowed) printf '%s\n' "host memory backend selection chooses SSE2 when the runtime policy allows it" ;;
	host-memcpy-sse2-backend-preserves-contract) printf '%s\n' "host memcpy preserves its contract on the SSE2 backend" ;;
	host-memset-sse2-backend-preserves-contract) printf '%s\n' "host memset preserves its contract on the SSE2 backend" ;;
	rust-defines-memcpy) printf '%s\n' "Rust defines memcpy in the kernel helper module" ;;
	rust-defines-memset) printf '%s\n' "Rust defines memset in the kernel helper module" ;;
	rust-defines-memory-backend-dispatch) printf '%s\n' "kernel memory family defines a canonical backend dispatch leaf" ;;
	memory-facade-exposes-backend-queries) printf '%s\n' "kernel memory facade exposes selected backend queries" ;;
	rust-exports-kfs-memcpy) printf '%s\n' "kernel memory family exports kfs_memcpy" ;;
	rust-exports-kfs-memset) printf '%s\n' "kernel memory family exports kfs_memset" ;;
	rust-avoids-extern-memcpy) printf '%s\n' "kernel memory family does not fall back to extern memcpy" ;;
	rust-avoids-extern-memset) printf '%s\n' "kernel memory family does not fall back to extern memset" ;;
	release-kernel-exports-kfs-memcpy) printf '%s\n' "release kernel exports kfs_memcpy" ;;
	release-kernel-exports-kfs-memset) printf '%s\n' "release kernel exports kfs_memset" ;;
	memory-helpers-avoid-volatile-access) printf '%s\n' "memory helpers avoid volatile ordinary-memory access" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${SOURCE_CRATE}" ]] || die "missing memory helper family file: ${SOURCE_CRATE}"
	[[ -r "${SOURCE_IMPL}" ]] || die "missing memory helper implementation file: ${SOURCE_IMPL}"
}

find_memory_pattern() {
	local pattern="$1"
	shift

	if command -v rg >/dev/null 2>&1; then
		rg -n "${pattern}" -S "$@" >/dev/null
	else
		grep -En "${pattern}" "$@" >/dev/null
	fi
}

assert_memory_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2

	if ! find_memory_pattern "${pattern}" "$@"; then
		echo "FAIL src: missing ${label}"
		return 1
	fi

	echo "PASS src: ${label}"
}

assert_no_memory_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2

	if find_memory_pattern "${pattern}" "$@"; then
		echo "FAIL src: found ${label}"
		if command -v rg >/dev/null 2>&1; then
			rg -n "${pattern}" -S "$@" || true
		else
			grep -En "${pattern}" "$@" || true
		fi
		return 1
	fi

	echo "PASS src: no ${label}"
}

run_host_tests() {
	local filter="$1"
	local test_bin="build/ut_memory"

	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

assert_release_symbol() {
	local symbol="$1"
	local kernel="build/kernel-${ARCH}.bin"

	[[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make test-artifacts arch=${ARCH})"
	nm -n "${kernel}" | grep -qE "[[:space:]]T[[:space:]]+${symbol}$"

	echo "PASS ${kernel}: ${symbol}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-memcpy-unit-tests-pass)
		run_host_tests 'memcpy_basic_copy'
		;;
	host-memcpy-zero-length-behavior)
		run_host_tests 'memcpy_zero_length_keeps_destination'
		;;
	host-memcpy-return-pointer-behavior)
		run_host_tests 'memcpy_returns_original_destination_pointer'
		;;
	host-memcpy-same-pointer)
		run_host_tests 'memcpy_allows_same_pointer'
		;;
	host-memcpy-unaligned-pointers)
		run_host_tests 'memcpy_unaligned_pointers'
		;;
	host-memcpy-sentinel-bounds)
		run_host_tests 'memcpy_preserves_outside_range'
		;;
	host-memset-unit-tests-pass)
		run_host_tests 'memset_basic_fill'
		;;
	host-memset-zero-byte-fill)
		run_host_tests 'memset_zero_byte_fill'
		;;
	host-memset-zero-length-behavior)
		run_host_tests 'memset_zero_length_keeps_buffer'
		;;
	host-memset-return-pointer-behavior)
		run_host_tests 'memset_returns_original_destination_pointer'
		;;
	host-memset-sentinel-bounds)
		run_host_tests 'memset_partial_range_preserves_edges'
		;;
	host-memory-backends-default-to-scalar)
		run_host_tests 'memory_backends_default_to_scalar_when_policy_is_uninitialized'
		;;
	host-memory-backends-stay-scalar-when-runtime-owned)
		run_host_tests 'memory_backends_remain_scalar_when_runtime_is_owned_but_acceleration_is_deferred'
		;;
	host-memory-backends-stay-scalar-when-runtime-blocked)
		run_host_tests 'memory_backends_remain_scalar_when_policy_is_runtime_blocked'
		;;
	host-memory-backends-choose-sse2-when-allowed)
		run_host_tests 'memory_backends_choose_sse2_when_policy_allows_it'
		;;
	host-memcpy-sse2-backend-preserves-contract)
		run_host_tests 'memcpy_sse2_backend_preserves_existing_contract'
		;;
	host-memset-sse2-backend-preserves-contract)
		run_host_tests 'memset_sse2_backend_preserves_existing_contract'
		;;
	rust-defines-memcpy)
		assert_memory_pattern '\bfn[[:space:]]+memcpy\b' 'memcpy definition' "${SOURCE_IMPL}"
		;;
	rust-defines-memset)
		assert_memory_pattern '\bfn[[:space:]]+memset\b' 'memset definition' "${SOURCE_IMPL}"
		;;
	rust-defines-memory-backend-dispatch)
		assert_memory_pattern '\bmod[[:space:]]+dispatch\b' 'memory dispatch module' "${SOURCE_CRATE}"
		assert_memory_pattern '\benum[[:space:]]+MemoryBackend\b' 'MemoryBackend enum' 'src/kernel/klib/memory/dispatch.rs'
		;;
	memory-facade-exposes-backend-queries)
		assert_memory_pattern '\bfn[[:space:]]+memcpy_backend\b' 'memcpy backend query' "${SOURCE_CRATE}"
		assert_memory_pattern '\bfn[[:space:]]+memset_backend\b' 'memset backend query' "${SOURCE_CRATE}"
		;;
	rust-exports-kfs-memcpy)
		assert_memory_pattern '#\[no_mangle\]' 'no_mangle marker for exported helper wrappers' "${SOURCE_CRATE}"
		assert_memory_pattern 'pub[[:space:]]+unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_memcpy\b' 'kfs_memcpy wrapper export' "${SOURCE_CRATE}"
		;;
	rust-exports-kfs-memset)
		assert_memory_pattern '#\[no_mangle\]' 'no_mangle marker for exported helper wrappers' "${SOURCE_CRATE}"
		assert_memory_pattern 'pub[[:space:]]+unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_memset\b' 'kfs_memset wrapper export' "${SOURCE_CRATE}"
		;;
	rust-avoids-extern-memcpy)
		assert_no_memory_pattern 'extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+memcpy\b' 'extern memcpy fallback' "${SOURCE_CRATE}" "${SOURCE_IMPL}"
		;;
	rust-avoids-extern-memset)
		assert_no_memory_pattern 'extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+memset\b' 'extern memset fallback' "${SOURCE_CRATE}" "${SOURCE_IMPL}"
		;;
	release-kernel-exports-kfs-memcpy)
		assert_release_symbol 'kfs_memcpy'
		;;
	release-kernel-exports-kfs-memset)
		assert_release_symbol 'kfs_memset'
		;;
	memory-helpers-avoid-volatile-access)
		assert_no_memory_pattern 'read_volatile|write_volatile' 'volatile ordinary-memory access in memory helpers' "${SOURCE_IMPL}"
		;;
	*)
		die "usage: $0 <arch> {host-memcpy-unit-tests-pass|host-memcpy-zero-length-behavior|host-memcpy-return-pointer-behavior|host-memcpy-same-pointer|host-memcpy-unaligned-pointers|host-memcpy-sentinel-bounds|host-memset-unit-tests-pass|host-memset-zero-byte-fill|host-memset-zero-length-behavior|host-memset-return-pointer-behavior|host-memset-sentinel-bounds|host-memory-backends-default-to-scalar|host-memory-backends-stay-scalar-when-runtime-owned|host-memory-backends-stay-scalar-when-runtime-blocked|host-memory-backends-choose-sse2-when-allowed|host-memcpy-sse2-backend-preserves-contract|host-memset-sse2-backend-preserves-contract|rust-defines-memcpy|rust-defines-memset|rust-defines-memory-backend-dispatch|memory-facade-exposes-backend-queries|rust-exports-kfs-memcpy|rust-exports-kfs-memset|rust-avoids-extern-memcpy|rust-avoids-extern-memset|release-kernel-exports-kfs-memcpy|release-kernel-exports-kfs-memset|memory-helpers-avoid-volatile-access}"
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

	[[ -n "${CASE}" ]] || die "usage: $0 <arch> <case>"
	run_direct_case
}

main "$@"
