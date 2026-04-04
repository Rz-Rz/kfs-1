#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SOCKET_PATH="${REPO_ROOT}/build/ui-interaction-${ARCH}-${CASE}.vnc"
QMP_SOCKET_PATH="${REPO_ROOT}/build/ui-interaction-${ARCH}-${CASE}.qmp"
LOG_PATH="${REPO_ROOT}/build/ui-interaction-${ARCH}-${CASE}.log"
source "$(dirname "${BASH_SOURCE[0]}")/lib/qemu-vnc.bash"

list_cases() {
	cat <<'EOF'
f11-creates-terminal-and-label-becomes-beta
f12-destroys-current-terminal-and-label-returns-alpha
terminal-switching-preserves-screen-contents
alt-a-c-creates-terminal-and-label-becomes-beta
alt-a-x-destroys-terminal-and-label-returns-alpha
alt-a-digit-selects-target-terminal
bare-function-key-selection-matrix
alt-function-key-selection-matrix
destroying-last-terminal-keeps-alpha-active
terminal-create-capacity-limit-is-a-no-op
switching-to-an-untouched-terminal-shows-a-blank-screen
switching-back-from-an-untouched-terminal-restores-the-dirty-terminal
destroying-from-a-high-slot-focuses-a-valid-survivor
arrow-up-restores-an-older-viewport-snapshot
arrow-down-returns-to-the-live-tail-viewport
multi-line-output-scrolls-visibly-after-repeated-newlines
backspace-blanks-the-last-visible-character-cell
newline-moves-visible-output-to-the-next-row
end-of-line-wrap-continues-on-the-next-row
switching-back-to-a-scrolled-terminal-restores-its-viewport
label-overlay-right-aligns-short-labels
label-overlay-clears-stale-cells-when-shortening
EOF
}

describe_case() {
	case "$1" in
	f11-creates-terminal-and-label-becomes-beta) printf '%s\n' "host-driven VNC E2E maps F11 onto terminal creation and updates the visible label" ;;
	f12-destroys-current-terminal-and-label-returns-alpha) printf '%s\n' "host-driven VNC E2E maps F12 onto terminal destruction and returns focus to alpha" ;;
	terminal-switching-preserves-screen-contents) printf '%s\n' "host-driven VNC E2E preserves isolated screen contents when switching terminals" ;;
	alt-a-c-creates-terminal-and-label-becomes-beta) printf '%s\n' "host-driven VNC E2E maps Alt+A then C onto terminal creation" ;;
	alt-a-x-destroys-terminal-and-label-returns-alpha) printf '%s\n' "host-driven VNC E2E maps Alt+A then X onto terminal destruction" ;;
	alt-a-digit-selects-target-terminal) printf '%s\n' "host-driven VNC E2E maps Alt+A then a digit onto terminal selection" ;;
	bare-function-key-selection-matrix) printf '%s\n' "host-driven VNC E2E maps bare F1 through F10 onto visible terminal selection" ;;
	alt-function-key-selection-matrix) printf '%s\n' "host-driven VNC E2E maps Alt+F1 through Alt+F12 onto visible terminal selection" ;;
	destroying-last-terminal-keeps-alpha-active) printf '%s\n' "host-driven VNC E2E keeps alpha active when destroying the last remaining terminal" ;;
	terminal-create-capacity-limit-is-a-no-op) printf '%s\n' "host-driven VNC E2E keeps the active label unchanged when creating beyond terminal capacity" ;;
	switching-to-an-untouched-terminal-shows-a-blank-screen) printf '%s\n' "host-driven VNC E2E shows a blank screen on an untouched terminal" ;;
	switching-back-from-an-untouched-terminal-restores-the-dirty-terminal) printf '%s\n' "host-driven VNC E2E restores the dirty terminal after switching back from an untouched one" ;;
	destroying-from-a-high-slot-focuses-a-valid-survivor) printf '%s\n' "host-driven VNC E2E focuses a surviving terminal after destroying the highest active slot" ;;
	arrow-up-restores-an-older-viewport-snapshot) printf '%s\n' "host-driven VNC E2E lets ArrowUp restore an older viewport snapshot" ;;
	arrow-down-returns-to-the-live-tail-viewport) printf '%s\n' "host-driven VNC E2E lets ArrowDown return to the live tail viewport" ;;
	multi-line-output-scrolls-visibly-after-repeated-newlines) printf '%s\n' "host-driven VNC E2E visibly scrolls after repeated newline output" ;;
	backspace-blanks-the-last-visible-character-cell) printf '%s\n' "host-driven VNC E2E blanks the last visible character cell on Backspace" ;;
	newline-moves-visible-output-to-the-next-row) printf '%s\n' "host-driven VNC E2E moves visible output to the next row on Enter" ;;
	end-of-line-wrap-continues-on-the-next-row) printf '%s\n' "host-driven VNC E2E wraps visible output onto the next row at line end" ;;
	switching-back-to-a-scrolled-terminal-restores-its-viewport) printf '%s\n' "host-driven VNC E2E restores a scrolled terminal viewport after switching away and back" ;;
	label-overlay-right-aligns-short-labels) printf '%s\n' "host-driven VNC E2E keeps short labels right-aligned with blank leading padding" ;;
	label-overlay-clears-stale-cells-when-shortening) printf '%s\n' "host-driven VNC E2E clears stale label cells when switching from a longer label back to a shorter one" ;;
	*) return 1 ;;
	esac
}

run_case() {
	local timeout_secs="${TEST_TIMEOUT_SECS:-15}"

	case "${CASE}" in
	bare-function-key-selection-matrix | alt-function-key-selection-matrix | arrow-up-restores-an-older-viewport-snapshot | arrow-down-returns-to-the-live-tail-viewport | multi-line-output-scrolls-visibly-after-repeated-newlines | backspace-blanks-the-last-visible-character-cell | newline-moves-visible-output-to-the-next-row | end-of-line-wrap-continues-on-the-next-row | switching-back-to-a-scrolled-terminal-restores-its-viewport | label-overlay-right-aligns-short-labels | label-overlay-clears-stale-cells-when-shortening)
		timeout_secs="${TEST_TIMEOUT_SECS:-60}"
		;;
	esac

	qemu_vnc_run_case "${ARCH}" "iso" "build/os-${ARCH}.iso" "${SOCKET_PATH}" "${QMP_SOCKET_PATH}" "${CASE}" "${LOG_PATH}" "${timeout_secs}"
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

	describe_case "${CASE}" >/dev/null 2>&1 || qemu_vnc_die "unknown case: ${CASE}"
	run_case
}

main "$@"
