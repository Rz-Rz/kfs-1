#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-15}"
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
    *) return 1 ;;
  esac
}

run_case() {
  local timeout_secs="${TEST_TIMEOUT_SECS:-15}"

  case "${CASE}" in
    bare-function-key-selection-matrix|alt-function-key-selection-matrix)
      timeout_secs="${TEST_TIMEOUT_SECS:-45}"
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
