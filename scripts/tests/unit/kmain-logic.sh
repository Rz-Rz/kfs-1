#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_layout_and_vga_cell.rs"
RANGE_SOURCE="src/kernel/types/range.rs"
DRIVER_SOURCE="src/kernel/drivers/vga_text/mod.rs"
ENTRY_SOURCE="src/kernel/core/entry.rs"
INIT_SOURCE="src/kernel/core/init.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

list_cases() {
	cat <<'EOF'
host-layout-order-unit-tests-pass
host-vga-cell-unit-tests-pass
rust-defines-layout-order-check
rust-defines-vga-text-cell
static-entry-calls-core-init-sequence
static-entry-references-console-loop
static-core-init-references-console-write
EOF
}

describe_case() {
	case "$1" in
	host-layout-order-unit-tests-pass) printf '%s\n' "host layout-order unit tests pass" ;;
	host-vga-cell-unit-tests-pass) printf '%s\n' "host VGA text cell unit tests pass" ;;
	rust-defines-layout-order-check) printf '%s\n' "Rust defines the pure layout-order helper" ;;
	rust-defines-vga-text-cell) printf '%s\n' "Rust defines the VGA text cell helper" ;;
	static-entry-calls-core-init-sequence) printf '%s\n' "static source check: entry references the early-init sequence" ;;
	static-entry-references-console-loop) printf '%s\n' "static source check: entry references the console loop path" ;;
	static-core-init-references-console-write) printf '%s\n' "static source check: core init references the console write call" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${RANGE_SOURCE}" ]] || die "missing range source: ${RANGE_SOURCE}"
	[[ -r "${DRIVER_SOURCE}" ]] || die "missing VGA driver source: ${DRIVER_SOURCE}"
	[[ -r "${ENTRY_SOURCE}" ]] || die "missing core entry source: ${ENTRY_SOURCE}"
	[[ -r "${INIT_SOURCE}" ]] || die "missing core init source: ${INIT_SOURCE}"
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

run_host_tests() {
	local filter="$1"
	local test_bin="build/ut_kmain_logic_${filter%_}"

	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-layout-order-unit-tests-pass)
		run_host_tests 'layout_order_'
		;;
	host-vga-cell-unit-tests-pass)
		run_host_tests 'vga_text_cell_'
		;;
	rust-defines-layout-order-check)
		assert_pattern '\bfn[[:space:]]+layout_order_is_sane\b' 'layout_order_is_sane definition' "${RANGE_SOURCE}"
		;;
	rust-defines-vga-text-cell)
		assert_pattern '\bfn[[:space:]]+vga_text_cell\b' 'vga_text_cell definition' "${DRIVER_SOURCE}"
		;;
	static-entry-calls-core-init-sequence)
		assert_pattern '\brun_early_init\(' 'kmain call to core init sequencing' "${ENTRY_SOURCE}"
		;;
	static-entry-references-console-loop)
		assert_pattern '\bconsole::start_keyboard_echo_loop\(' 'kmain success path reaches console loop' "${ENTRY_SOURCE}"
		;;
	static-core-init-references-console-write)
		assert_pattern '\bconsole::write_bytes\(b"42"\)' 'core init writes 42 through services console' "${INIT_SOURCE}"
		;;
	*)
		die "usage: $0 <arch> {host-layout-order-unit-tests-pass|host-vga-cell-unit-tests-pass|rust-defines-layout-order-check|rust-defines-vga-text-cell|static-entry-calls-core-init-sequence|static-entry-references-console-loop|static-core-init-references-console-write}"
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
