#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-15}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SOCKET_PATH="${REPO_ROOT}/build/compact-geometry-${ARCH}-${CASE}.vnc"
QMP_SOCKET_PATH="${REPO_ROOT}/build/compact-geometry-${ARCH}-${CASE}.qmp"
LOG_PATH="${REPO_ROOT}/build/compact-geometry-${ARCH}-${CASE}.log"
source "$(dirname "${BASH_SOURCE[0]}")/lib/qemu-vnc.bash"

list_cases() {
	cat <<'EOF'
compact-geometry-centers-42-in-physical-vga
compact-geometry-keeps-terminal-label-in-physical-top-right
compact-create-terminal-keeps-output-centered
compact-switching-restores-centered-terminal-contents
compact-destroy-restores-previous-terminal
compact-scroll-keeps-output-inside-centered-viewport
EOF
}

describe_case() {
	case "$1" in
	compact-geometry-centers-42-in-physical-vga) printf '%s\n' "host-driven VNC E2E keeps the compact40x10 boot text centered in physical VGA space" ;;
	compact-geometry-keeps-terminal-label-in-physical-top-right) printf '%s\n' "host-driven VNC E2E keeps the compact40x10 terminal label in the physical top-right overlay region" ;;
	compact-create-terminal-keeps-output-centered) printf '%s\n' "host-driven VNC E2E keeps compact terminal output inside the centered viewport after terminal creation" ;;
	compact-switching-restores-centered-terminal-contents) printf '%s\n' "host-driven VNC E2E restores centered compact terminal contents when switching terminals" ;;
	compact-destroy-restores-previous-terminal) printf '%s\n' "host-driven VNC E2E restores the previous compact terminal after destroying the active one" ;;
	compact-scroll-keeps-output-inside-centered-viewport) printf '%s\n' "host-driven VNC E2E keeps compact scrolling output inside the centered viewport" ;;
	*) return 1 ;;
	esac
}

run_case() {
	local timeout_secs="${TIMEOUT_SECS}"

	case "${CASE}" in
	compact-create-terminal-keeps-output-centered | compact-switching-restores-centered-terminal-contents | compact-destroy-restores-previous-terminal | compact-scroll-keeps-output-inside-centered-viewport)
		timeout_secs="${TEST_TIMEOUT_SECS:-60}"
		;;
	esac

	qemu_vnc_run_case "${ARCH}" "iso" "build/os-${ARCH}-compact40x10.iso" "${SOCKET_PATH}" "${QMP_SOCKET_PATH}" "${CASE}" "${LOG_PATH}" "${timeout_secs}" "compact40x10"
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
