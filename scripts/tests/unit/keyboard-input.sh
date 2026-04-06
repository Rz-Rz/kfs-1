#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCANCODE_TEST_SOURCE="tests/host_scancode.rs"
ECHO_TEST_SOURCE="tests/host_keyboard_echo.rs"
SOURCE_DRIVER="src/kernel/drivers/keyboard/mod.rs"
SOURCE_IMPL="src/kernel/drivers/keyboard/imp.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
host-keyboard-input-letter-key-press-maps-to-printable-ascii
host-keyboard-input-shift-changes-letter-case-until-release
host-keyboard-input-enter-and-backspace-decode-as-control-keys
host-keyboard-input-alt-function-key-is-distinguishable-for-shortcuts
host-keyboard-input-control-modifier-tracks-press-and-release
host-keyboard-input-extended-right-alt-updates-modifier-state
host-keyboard-input-extended-up-arrow-decodes-as-a-navigation-key
host-keyboard-input-extended-down-arrow-decodes-as-a-navigation-key
host-keyboard-input-break-codes-become-release-events
host-keyboard-input-printable-input-routes-to-screen-byte-output
host-keyboard-input-enter-routes-to-the-shared-newline-path
host-keyboard-input-backspace-routes-to-the-erase-operation
host-keyboard-input-up-arrow-routes-to-history-viewport-movement
host-keyboard-input-down-arrow-routes-to-history-viewport-movement
host-keyboard-input-key-release-events-do-not-echo
host-keyboard-input-alt-function-shortcuts-are-intercepted-instead-of-echoed
host-keyboard-input-bare-function-keys-select-terminals-without-echoing-text
host-keyboard-input-f11-creates-a-terminal-without-a-prefix-key
host-keyboard-input-f12-destroys-the-current-terminal-without-a-prefix-key
host-keyboard-input-shortcut-terminal-indices-cover-alt-functions-and-command-selectors
host-keyboard-input-direct-function-shortcuts-cover-select-create-and-destroy
host-keyboard-input-alt-modified-printable-input-does-not-leave-garbage-text
host-keyboard-input-ctrl-modified-printable-input-does-not-echo-text
source-defines-keyboard-decoder
source-defines-keyboard-polling-facade
EOF
}

describe_case() {
	case "$1" in
	host-keyboard-input-letter-key-press-maps-to-printable-ascii) printf '%s\n' "host keyboard scancode decoding maps a letter press to printable ASCII" ;;
	host-keyboard-input-shift-changes-letter-case-until-release) printf '%s\n' "host keyboard scancode decoding keeps shift state until release" ;;
	host-keyboard-input-enter-and-backspace-decode-as-control-keys) printf '%s\n' "host keyboard scancode decoding recognizes enter and backspace" ;;
	host-keyboard-input-alt-function-key-is-distinguishable-for-shortcuts) printf '%s\n' "host keyboard scancode decoding keeps alt-function shortcuts distinct" ;;
	host-keyboard-input-control-modifier-tracks-press-and-release) printf '%s\n' "host keyboard scancode decoding tracks control press and release state" ;;
	host-keyboard-input-extended-right-alt-updates-modifier-state) printf '%s\n' "host keyboard scancode decoding updates right-alt modifier state" ;;
	host-keyboard-input-extended-up-arrow-decodes-as-a-navigation-key) printf '%s\n' "host keyboard scancode decoding recognizes the extended up arrow" ;;
	host-keyboard-input-extended-down-arrow-decodes-as-a-navigation-key) printf '%s\n' "host keyboard scancode decoding recognizes the extended down arrow" ;;
	host-keyboard-input-break-codes-become-release-events) printf '%s\n' "host keyboard scancode decoding turns break codes into release events" ;;
	host-keyboard-input-printable-input-routes-to-screen-byte-output) printf '%s\n' "host keyboard routing sends printable input to screen bytes" ;;
	host-keyboard-input-enter-routes-to-the-shared-newline-path) printf '%s\n' "host keyboard routing turns enter into a newline byte" ;;
	host-keyboard-input-backspace-routes-to-the-erase-operation) printf '%s\n' "host keyboard routing sends backspace to the erase path" ;;
	host-keyboard-input-up-arrow-routes-to-history-viewport-movement) printf '%s\n' "host keyboard routing sends up arrow to viewport-up" ;;
	host-keyboard-input-down-arrow-routes-to-history-viewport-movement) printf '%s\n' "host keyboard routing sends down arrow to viewport-down" ;;
	host-keyboard-input-key-release-events-do-not-echo) printf '%s\n' "host keyboard routing suppresses release events" ;;
	host-keyboard-input-alt-function-shortcuts-are-intercepted-instead-of-echoed) printf '%s\n' "host keyboard routing intercepts alt-function shortcuts" ;;
	host-keyboard-input-bare-function-keys-select-terminals-without-echoing-text) printf '%s\n' "host keyboard routing maps bare function keys onto terminal-selection commands" ;;
	host-keyboard-input-f11-creates-a-terminal-without-a-prefix-key) printf '%s\n' "host keyboard routing maps F11 onto terminal creation" ;;
	host-keyboard-input-f12-destroys-the-current-terminal-without-a-prefix-key) printf '%s\n' "host keyboard routing maps F12 onto terminal destruction" ;;
	host-keyboard-input-shortcut-terminal-indices-cover-alt-functions-and-command-selectors) printf '%s\n' "host keyboard shortcut helpers map alt-function and selector commands to terminal indices" ;;
	host-keyboard-input-direct-function-shortcuts-cover-select-create-and-destroy) printf '%s\n' "host keyboard shortcut helpers map direct function keys to select/create/destroy commands" ;;
	host-keyboard-input-alt-modified-printable-input-does-not-leave-garbage-text) printf '%s\n' "host keyboard routing suppresses alt-modified printable input" ;;
	host-keyboard-input-ctrl-modified-printable-input-does-not-echo-text) printf '%s\n' "host keyboard routing suppresses ctrl-modified printable input" ;;
	source-defines-keyboard-decoder) printf '%s\n' "keyboard driver defines the decoder and routing helpers" ;;
	source-defines-keyboard-polling-facade) printf '%s\n' "keyboard driver defines the polling facade" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
	[[ -r "${SCANCODE_TEST_SOURCE}" ]] || die "missing host unit test source: ${SCANCODE_TEST_SOURCE}"
	[[ -r "${ECHO_TEST_SOURCE}" ]] || die "missing host unit test source: ${ECHO_TEST_SOURCE}"
	[[ -r "${SOURCE_DRIVER}" ]] || die "missing keyboard driver source: ${SOURCE_DRIVER}"
	[[ -r "${SOURCE_IMPL}" ]] || die "missing keyboard driver implementation: ${SOURCE_IMPL}"
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
	local source="$1"
	local filter="$2"
	local test_bin="build/ut_keyboard_input_${filter%_}"

	mkdir -p "$(dirname "${test_bin}")"
	run_host_rust_test "${source}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-keyboard-input-letter-key-press-maps-to-printable-ascii)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'letter_key_press_maps_to_printable_ascii'
		;;
	host-keyboard-input-shift-changes-letter-case-until-release)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'shift_changes_letter_case_until_release'
		;;
	host-keyboard-input-enter-and-backspace-decode-as-control-keys)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'enter_and_backspace_decode_as_control_keys'
		;;
	host-keyboard-input-alt-function-key-is-distinguishable-for-shortcuts)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'alt_function_key_is_distinguishable_for_shortcuts'
		;;
	host-keyboard-input-control-modifier-tracks-press-and-release)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'control_modifier_tracks_press_and_release'
		;;
	host-keyboard-input-extended-right-alt-updates-modifier-state)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'extended_right_alt_updates_modifier_state'
		;;
	host-keyboard-input-extended-up-arrow-decodes-as-a-navigation-key)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'extended_up_arrow_decodes_as_a_navigation_key'
		;;
	host-keyboard-input-extended-down-arrow-decodes-as-a-navigation-key)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'extended_down_arrow_decodes_as_a_navigation_key'
		;;
	host-keyboard-input-break-codes-become-release-events)
		run_host_tests "${SCANCODE_TEST_SOURCE}" 'break_codes_become_release_events'
		;;
	host-keyboard-input-printable-input-routes-to-screen-byte-output)
		run_host_tests "${ECHO_TEST_SOURCE}" 'printable_input_routes_to_screen_byte_output'
		;;
	host-keyboard-input-enter-routes-to-the-shared-newline-path)
		run_host_tests "${ECHO_TEST_SOURCE}" 'enter_routes_to_the_shared_newline_path'
		;;
	host-keyboard-input-backspace-routes-to-the-erase-operation)
		run_host_tests "${ECHO_TEST_SOURCE}" 'backspace_routes_to_the_erase_operation'
		;;
	host-keyboard-input-up-arrow-routes-to-history-viewport-movement)
		run_host_tests "${ECHO_TEST_SOURCE}" 'up_arrow_routes_to_history_viewport_movement'
		;;
	host-keyboard-input-down-arrow-routes-to-history-viewport-movement)
		run_host_tests "${ECHO_TEST_SOURCE}" 'down_arrow_routes_to_history_viewport_movement'
		;;
	host-keyboard-input-key-release-events-do-not-echo)
		run_host_tests "${ECHO_TEST_SOURCE}" 'key_release_events_do_not_echo'
		;;
	host-keyboard-input-alt-function-shortcuts-are-intercepted-instead-of-echoed)
		run_host_tests "${ECHO_TEST_SOURCE}" 'alt_function_shortcuts_are_intercepted_instead_of_echoed'
		;;
	host-keyboard-input-bare-function-keys-select-terminals-without-echoing-text)
		run_host_tests "${ECHO_TEST_SOURCE}" 'bare_function_keys_select_terminals_without_echoing_text'
		;;
	host-keyboard-input-f11-creates-a-terminal-without-a-prefix-key)
		run_host_tests "${ECHO_TEST_SOURCE}" 'f11_creates_a_terminal_without_a_prefix_key'
		;;
	host-keyboard-input-f12-destroys-the-current-terminal-without-a-prefix-key)
		run_host_tests "${ECHO_TEST_SOURCE}" 'f12_destroys_the_current_terminal_without_a_prefix_key'
		;;
	host-keyboard-input-shortcut-terminal-indices-cover-alt-functions-and-command-selectors)
		run_host_tests "${ECHO_TEST_SOURCE}" 'shortcut_terminal_indices_cover_alt_functions_and_command_selectors'
		;;
	host-keyboard-input-direct-function-shortcuts-cover-select-create-and-destroy)
		run_host_tests "${ECHO_TEST_SOURCE}" 'direct_function_shortcuts_cover_select_create_and_destroy'
		;;
	host-keyboard-input-alt-modified-printable-input-does-not-leave-garbage-text)
		run_host_tests "${ECHO_TEST_SOURCE}" 'alt_modified_printable_input_does_not_leave_garbage_text'
		;;
	host-keyboard-input-ctrl-modified-printable-input-does-not-echo-text)
		run_host_tests "${ECHO_TEST_SOURCE}" 'ctrl_modified_printable_input_does_not_echo_text'
		;;
	source-defines-keyboard-decoder)
		assert_pattern '\bdecode_scancode\b|\broute_key_event\b|\bKeyboardState\b|\bKeyboardRoute\b|\bdirect_function_shortcut\b|\bshortcut_terminal_index\b' 'keyboard decode and routing helpers' "${SOURCE_IMPL}"
		;;
	source-defines-keyboard-polling-facade)
		assert_pattern '\bkeyboard_init\b|\bkeyboard_poll_route\b' 'keyboard polling facade' "${SOURCE_DRIVER}"
		;;
	*)
		die "usage: $0 <arch> {host-keyboard-input-letter-key-press-maps-to-printable-ascii|host-keyboard-input-shift-changes-letter-case-until-release|host-keyboard-input-enter-and-backspace-decode-as-control-keys|host-keyboard-input-alt-function-key-is-distinguishable-for-shortcuts|host-keyboard-input-control-modifier-tracks-press-and-release|host-keyboard-input-extended-right-alt-updates-modifier-state|host-keyboard-input-extended-up-arrow-decodes-as-a-navigation-key|host-keyboard-input-extended-down-arrow-decodes-as-a-navigation-key|host-keyboard-input-break-codes-become-release-events|host-keyboard-input-printable-input-routes-to-screen-byte-output|host-keyboard-input-enter-routes-to-the-shared-newline-path|host-keyboard-input-backspace-routes-to-the-erase-operation|host-keyboard-input-up-arrow-routes-to-history-viewport-movement|host-keyboard-input-down-arrow-routes-to-history-viewport-movement|host-keyboard-input-key-release-events-do-not-echo|host-keyboard-input-alt-function-shortcuts-are-intercepted-instead-of-echoed|host-keyboard-input-bare-function-keys-select-terminals-without-echoing-text|host-keyboard-input-f11-creates-a-terminal-without-a-prefix-key|host-keyboard-input-f12-destroys-the-current-terminal-without-a-prefix-key|host-keyboard-input-shortcut-terminal-indices-cover-alt-functions-and-command-selectors|host-keyboard-input-direct-function-shortcuts-cover-select-create-and-destroy|host-keyboard-input-alt-modified-printable-input-does-not-leave-garbage-text|host-keyboard-input-ctrl-modified-printable-input-does-not-echo-text|source-defines-keyboard-decoder|source-defines-keyboard-polling-facade}"
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
