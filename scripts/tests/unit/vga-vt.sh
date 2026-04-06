#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_vt.rs"
SOURCE_DRIVER="src/kernel/drivers/vga_text/mod.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
host-vga-vt-terminal-buffers-keep-output-and-cursor-state-isolated
host-vga-vt-active-terminal-selection-keeps-each-buffer-intact
host-vga-vt-creating-a-terminal-focuses-the-new-terminal
host-vga-vt-destroying-the-current-terminal-removes-it-from-the-active-order
host-vga-vt-switching-active-terminal-changes-the-visible-view
host-vga-vt-switching-back-to-a-scrolled-terminal-preserves-backspace-history
host-vga-vt-terminal-label-overlay-changes-with-active-label-index
source-defines-vga-terminal-bank
source-defines-active-terminal-selector
source-defines-terminal-lifecycle
source-defines-terminal-label-overlay
EOF
}

describe_case() {
	case "$1" in
	host-vga-vt-terminal-buffers-keep-output-and-cursor-state-isolated) printf '%s\n' "host virtual terminals keep retained output and cursor state isolated per terminal" ;;
	host-vga-vt-active-terminal-selection-keeps-each-buffer-intact) printf '%s\n' "host virtual terminals keep each buffer intact when the active terminal changes" ;;
	host-vga-vt-creating-a-terminal-focuses-the-new-terminal) printf '%s\n' "host virtual terminals focus the new terminal when creating it" ;;
	host-vga-vt-destroying-the-current-terminal-removes-it-from-the-active-order) printf '%s\n' "host virtual terminals remove the current screen from the active order when destroying it" ;;
	host-vga-vt-switching-active-terminal-changes-the-visible-view) printf '%s\n' "host virtual terminals switch the visible view when the active screen changes" ;;
	host-vga-vt-switching-back-to-a-scrolled-terminal-preserves-backspace-history) printf '%s\n' "host virtual terminals preserve backspace history when switching back to a scrolled terminal" ;;
	host-vga-vt-terminal-label-overlay-changes-with-active-label-index) printf '%s\n' "host virtual terminals change the active-indicator overlay when the active label index changes" ;;
	source-defines-vga-terminal-bank) printf '%s\n' "VGA text driver defines the virtual terminal bank model" ;;
	source-defines-active-terminal-selector) printf '%s\n' "VGA text driver exposes active-terminal selection" ;;
	source-defines-terminal-lifecycle) printf '%s\n' "VGA text driver defines terminal create and destroy lifecycle operations" ;;
	source-defines-terminal-label-overlay) printf '%s\n' "VGA text driver defines active-indicator overlay helpers" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${SOURCE_DRIVER}" ]] || die "missing VGA text driver source: ${SOURCE_DRIVER}"
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
	local test_bin="build/ut_vga_vt_${filter%_}"

	mkdir -p "$(dirname "${test_bin}")"
	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-vga-vt-terminal-buffers-keep-output-and-cursor-state-isolated)
		run_host_tests 'terminal_buffers_keep_output_and_cursor_state_isolated'
		;;
	host-vga-vt-active-terminal-selection-keeps-each-buffer-intact)
		run_host_tests 'active_terminal_selection_keeps_each_buffer_intact'
		;;
	host-vga-vt-creating-a-terminal-focuses-the-new-terminal)
		run_host_tests 'creating_a_terminal_focuses_the_new_terminal'
		;;
	host-vga-vt-destroying-the-current-terminal-removes-it-from-the-active-order)
		run_host_tests 'destroying_the_current_terminal_removes_it_from_the_active_order'
		;;
	host-vga-vt-switching-active-terminal-changes-the-visible-view)
		run_host_tests 'switching_active_terminal_changes_the_visible_view'
		;;
	host-vga-vt-switching-back-to-a-scrolled-terminal-preserves-backspace-history)
		run_host_tests 'switching_back_to_a_scrolled_terminal_preserves_backspace_history'
		;;
	host-vga-vt-terminal-label-overlay-changes-with-active-label-index)
		run_host_tests 'terminal_label_overlay_changes_with_active_label_index'
		;;
	source-defines-vga-terminal-bank)
		assert_pattern '\bVgaTerminal\b|\bVgaTerminalBank\b|\bVGA_TEXT_TERMINAL_COUNT\b' 'virtual terminal bank model' "${SOURCE_DRIVER}"
		;;
	source-defines-active-terminal-selector)
		assert_pattern '\bactive_index\b|\bterminal_mut\b|\bset_active\b|\bvga_text_set_active_terminal\b' 'active terminal selector' "${SOURCE_DRIVER}"
		;;
	source-defines-terminal-lifecycle)
		assert_pattern '\bcreate_terminal\b|\bdestroy_active_terminal\b|\bvga_text_create_terminal\b|\bvga_text_destroy_terminal\b' 'terminal lifecycle operations' "${SOURCE_DRIVER}"
		;;
	source-defines-terminal-label-overlay)
		assert_pattern '\bterminal_label\b|\bbuild_terminal_label_cells\b|\bVGA_TEXT_TERMINAL_LABELS\b|\bVGA_TEXT_TERMINAL_LABEL_WIDTH\b' 'terminal label overlay helpers' "${SOURCE_DRIVER}"
		;;
	*)
		die "usage: $0 <arch> {host-vga-vt-terminal-buffers-keep-output-and-cursor-state-isolated|host-vga-vt-active-terminal-selection-keeps-each-buffer-intact|host-vga-vt-creating-a-terminal-focuses-the-new-terminal|host-vga-vt-destroying-the-current-terminal-removes-it-from-the-active-order|host-vga-vt-switching-active-terminal-changes-the-visible-view|host-vga-vt-switching-back-to-a-scrolled-terminal-preserves-backspace-history|host-vga-vt-terminal-label-overlay-changes-with-active-label-index|source-defines-vga-terminal-bank|source-defines-active-terminal-selector|source-defines-terminal-lifecycle|source-defines-terminal-label-overlay}"
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
