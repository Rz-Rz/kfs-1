#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_string.rs"
SOURCE_CRATE="src/kernel/klib/string/mod.rs"
SOURCE_IMPL="src/kernel/klib/string/imp.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

list_cases() {
	cat <<'EOF'
host-strlen-unit-tests-pass
host-strlen-embedded-nul-stops-first
host-strlen-unaligned-start
host-strlen-word-boundary
host-strcmp-unit-tests-pass
host-strcmp-prefix-and-empty-cases
host-strcmp-same-pointer
host-strcmp-high-byte-ordering
rust-defines-strlen
rust-defines-strcmp
rust-exports-kfs-strlen
rust-exports-kfs-strcmp
rust-avoids-extern-strlen
rust-avoids-extern-strcmp
release-kernel-exports-kfs-strlen
release-kernel-exports-kfs-strcmp
string-helpers-avoid-volatile-reads
EOF
}

describe_case() {
	case "$1" in
	host-strlen-unit-tests-pass) printf '%s\n' "host strlen baseline unit tests pass" ;;
	host-strlen-embedded-nul-stops-first) printf '%s\n' "host strlen stops at the first embedded NUL" ;;
	host-strlen-unaligned-start) printf '%s\n' "host strlen handles an unaligned starting pointer" ;;
	host-strlen-word-boundary) printf '%s\n' "host strlen handles strings that cross a natural word boundary" ;;
	host-strcmp-unit-tests-pass) printf '%s\n' "host strcmp baseline unit tests pass" ;;
	host-strcmp-prefix-and-empty-cases) printf '%s\n' "host strcmp handles prefix and empty/non-empty cases" ;;
	host-strcmp-same-pointer) printf '%s\n' "host strcmp returns equality for the same pointer" ;;
	host-strcmp-high-byte-ordering) printf '%s\n' "host strcmp uses unsigned-byte ordering for high-byte cases" ;;
	rust-defines-strlen) printf '%s\n' "Rust defines strlen in the kernel helper module" ;;
	rust-defines-strcmp) printf '%s\n' "Rust defines strcmp in the kernel helper module" ;;
	rust-exports-kfs-strlen) printf '%s\n' "kernel string family exports kfs_strlen" ;;
	rust-exports-kfs-strcmp) printf '%s\n' "kernel string family exports kfs_strcmp" ;;
	rust-avoids-extern-strlen) printf '%s\n' "kernel string family does not fall back to extern strlen" ;;
	rust-avoids-extern-strcmp) printf '%s\n' "kernel string family does not fall back to extern strcmp" ;;
	release-kernel-exports-kfs-strlen) printf '%s\n' "release kernel exports kfs_strlen" ;;
	release-kernel-exports-kfs-strcmp) printf '%s\n' "release kernel exports kfs_strcmp" ;;
	string-helpers-avoid-volatile-reads) printf '%s\n' "string helpers avoid volatile ordinary-memory reads" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${SOURCE_CRATE}" ]] || die "missing string helper crate: ${SOURCE_CRATE}"
	[[ -r "${SOURCE_IMPL}" ]] || die "missing string helper implementation: ${SOURCE_IMPL}"
}

find_string_pattern() {
	local pattern="$1"
	shift

	if command -v rg >/dev/null 2>&1; then
		rg -n "${pattern}" -S "$@" >/dev/null
	else
		grep -En "${pattern}" "$@" >/dev/null
	fi
}

assert_string_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2

	if ! find_string_pattern "${pattern}" "$@"; then
		echo "FAIL src: missing ${label}"
		return 1
	fi

	echo "PASS src: ${label}"
	return 0
}

assert_no_string_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2

	if find_string_pattern "${pattern}" "$@"; then
		echo "FAIL src: found ${label}"
		if command -v rg >/dev/null 2>&1; then
			rg -n "${pattern}" -S "$@" || true
		else
			grep -En "${pattern}" "$@" || true
		fi
		return 1
	fi

	echo "PASS src: ${label}"
	return 0
}

run_host_tests() {
	local filter="$1"
	local test_bin="build/ut_string_${filter%_}"

	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

assert_release_symbol() {
	local symbol="$1"
	local kernel="build/kernel-${ARCH}.bin"

	[[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make test-artifacts arch=${ARCH})"
	local symbol_table
	symbol_table="$(nm -n "${kernel}")"
	grep -qE "[[:space:]]T[[:space:]]+${symbol}$" <<<"${symbol_table}"

	echo "PASS ${kernel}: ${symbol}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-strlen-unit-tests-pass)
		run_host_tests 'strlen_empty_string'
		run_host_tests 'strlen_regular_string'
		;;
	host-strlen-embedded-nul-stops-first)
		run_host_tests 'strlen_embedded_nul_'
		;;
	host-strlen-unaligned-start)
		run_host_tests 'strlen_unaligned_start'
		;;
	host-strlen-word-boundary)
		run_host_tests 'strlen_crosses_natural_word_boundary'
		;;
	host-strcmp-unit-tests-pass)
		run_host_tests 'strcmp_equal_strings'
		run_host_tests 'strcmp_lexicographic_less'
		run_host_tests 'strcmp_lexicographic_greater'
		;;
	host-strcmp-prefix-and-empty-cases)
		run_host_tests 'strcmp_prefix'
		run_host_tests 'strcmp_empty_vs_non_empty'
		;;
	host-strcmp-same-pointer)
		run_host_tests 'strcmp_same_pointer'
		;;
	host-strcmp-high-byte-ordering)
		run_host_tests 'strcmp_high_byte_ordering'
		;;
	rust-defines-strlen)
		assert_string_pattern '\bfn[[:space:]]+strlen\b' 'strlen definition' "${SOURCE_IMPL}"
		;;
	rust-defines-strcmp)
		assert_string_pattern '\bfn[[:space:]]+strcmp\b' 'strcmp definition' "${SOURCE_IMPL}"
		;;
	rust-exports-kfs-strlen)
		assert_string_pattern '#\[no_mangle\]' 'no_mangle marker for exported helper wrappers' "${SOURCE_CRATE}"
		assert_string_pattern 'pub[[:space:]]+unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_strlen\b' 'kfs_strlen wrapper export' "${SOURCE_CRATE}"
		;;
	rust-exports-kfs-strcmp)
		assert_string_pattern '#\[no_mangle\]' 'no_mangle marker for exported helper wrappers' "${SOURCE_CRATE}"
		assert_string_pattern 'pub[[:space:]]+unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_strcmp\b' 'kfs_strcmp wrapper export' "${SOURCE_CRATE}"
		;;
	rust-avoids-extern-strlen)
		assert_no_string_pattern 'extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+strlen\b' 'extern strlen fallback' "${SOURCE_CRATE}" "${SOURCE_IMPL}"
		;;
	rust-avoids-extern-strcmp)
		assert_no_string_pattern 'extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+strcmp\b' 'extern strcmp fallback' "${SOURCE_CRATE}" "${SOURCE_IMPL}"
		;;
	release-kernel-exports-kfs-strlen)
		assert_release_symbol 'kfs_strlen'
		;;
	release-kernel-exports-kfs-strcmp)
		assert_release_symbol 'kfs_strcmp'
		;;
	string-helpers-avoid-volatile-reads)
		assert_no_string_pattern 'read_volatile' 'volatile ordinary-memory reads in string helpers' "${SOURCE_IMPL}"
		;;
	*)
		die "usage: $0 <arch> {host-strlen-unit-tests-pass|host-strlen-embedded-nul-stops-first|host-strlen-unaligned-start|host-strlen-word-boundary|host-strcmp-unit-tests-pass|host-strcmp-prefix-and-empty-cases|host-strcmp-same-pointer|host-strcmp-high-byte-ordering|rust-defines-strlen|rust-defines-strcmp|rust-exports-kfs-strlen|rust-exports-kfs-strcmp|rust-avoids-extern-strlen|rust-avoids-extern-strcmp|release-kernel-exports-kfs-strlen|release-kernel-exports-kfs-strcmp|string-helpers-avoid-volatile-reads}"
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

	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	run_direct_case
}

main "$@"
