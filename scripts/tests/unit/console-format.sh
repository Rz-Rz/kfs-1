#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_vga_format.rs"
SOURCE_CONSOLE="src/kernel/services/console.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
host-console-format-unit-tests-pass
source-defines-format-helpers
source-defines-printk-wrappers
EOF
}

describe_case() {
	case "$1" in
	host-console-format-unit-tests-pass) printf '%s\n' "host console format unit tests pass through the real crate boundary" ;;
	source-defines-format-helpers) printf '%s\n' "console service defines the no-allocation formatting helpers" ;;
	source-defines-printk-wrappers) printf '%s\n' "console service defines printf/printk wrapper entrypoints" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${SOURCE_CONSOLE}" ]] || die "missing console service source: ${SOURCE_CONSOLE}"
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
	local test_bin="build/ut_console_format"

	mkdir -p "$(dirname "${test_bin}")"
	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-console-format-unit-tests-pass)
		run_host_tests ''
		;;
	source-defines-format-helpers)
		assert_pattern '\bformat_usize_decimal\b|\bformat_usize_hex\b|\bformat_isize_decimal\b|\brender_printf_with_args\b' 'console formatting helpers' "${SOURCE_CONSOLE}"
		;;
	source-defines-printk-wrappers)
		assert_pattern '\bfn[[:space:]]+printf\b|\bfn[[:space:]]+printf_args\b|\bfn[[:space:]]+printk\b|\bfn[[:space:]]+printk_args\b' 'console printf/printk wrappers' "${SOURCE_CONSOLE}"
		;;
	*)
		die "usage: $0 <arch> {host-console-format-unit-tests-pass|source-defines-format-helpers|source-defines-printk-wrappers}"
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
