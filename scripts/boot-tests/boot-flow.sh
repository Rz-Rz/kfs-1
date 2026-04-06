#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-all}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-20}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SOCKET_PATH="${REPO_ROOT}/build/boot-flow-${ARCH}-${CASE}.vnc"
QMP_SOCKET_PATH="${REPO_ROOT}/build/boot-flow-${ARCH}-${CASE}.qmp"
LOG_PATH="${REPO_ROOT}/build/boot-flow-${ARCH}-${CASE}.log"
source "$(dirname "${BASH_SOURCE[0]}")/lib/qemu-vnc.bash"

list_cases() {
	cat <<'EOF'
boot-flow-renders-42-then-enters-live-console-loop
EOF
}

describe_case() {
	case "$1" in
	boot-flow-renders-42-then-enters-live-console-loop) printf '%s\n' "host-driven VNC E2E proves boot renders 42 before the live console loop accepts real input" ;;
	*) return 1 ;;
	esac
}

run_case() {
	qemu_vnc_run_case "${ARCH}" "iso" "build/os-${ARCH}.iso" "${SOCKET_PATH}" "${QMP_SOCKET_PATH}" "${CASE}" "${LOG_PATH}" "${TIMEOUT_SECS}"
}

run_all_cases() {
	local case_id
	while IFS= read -r case_id; do
		CASE="${case_id}"
		SOCKET_PATH="${REPO_ROOT}/build/boot-flow-${ARCH}-${CASE}.vnc"
		QMP_SOCKET_PATH="${REPO_ROOT}/build/boot-flow-${ARCH}-${CASE}.qmp"
		LOG_PATH="${REPO_ROOT}/build/boot-flow-${ARCH}-${CASE}.log"
		run_case
	done < <(list_cases)
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

	if [[ "${CASE}" == "all" ]]; then
		run_all_cases
		return 0
	fi

	describe_case "${CASE}" >/dev/null 2>&1 || qemu_vnc_die "unknown case: ${CASE}"
	run_case
}

main "$@"
