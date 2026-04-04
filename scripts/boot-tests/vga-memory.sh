#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-all}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-15}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SOCKET_PATH="${REPO_ROOT}/build/vga-memory-${ARCH}-${CASE}.vnc"
QMP_SOCKET_PATH="${REPO_ROOT}/build/vga-memory-${ARCH}-${CASE}.qmp"
LOG_PATH="${REPO_ROOT}/build/vga-memory-${ARCH}-${CASE}.log"
source "$(dirname "${BASH_SOURCE[0]}")/lib/qemu-vnc.bash"

list_cases() {
  cat <<'EOF'
vga-buffer-starts-with-42
vga-buffer-uses-default-attribute
vga-buffer-stable-across-snapshots
EOF
}

describe_case() {
  case "$1" in
    vga-buffer-starts-with-42) printf '%s\n' "host-driven VNC E2E shows the boot text in the visible top-left screen region" ;;
    vga-buffer-uses-default-attribute) printf '%s\n' "host-driven VNC E2E renders the boot text with the default visible VGA colors" ;;
    vga-buffer-stable-across-snapshots) printf '%s\n' "host-driven VNC E2E keeps the visible boot text stable across repeated framebuffer captures" ;;
    *) return 1 ;;
  esac
}

run_case() {
  local translated_case

  case "${CASE}" in
    vga-buffer-starts-with-42) translated_case="vga-buffer-starts-with-42" ;;
    vga-buffer-uses-default-attribute) translated_case="vga-buffer-uses-default-attribute" ;;
    vga-buffer-stable-across-snapshots) translated_case="vga-buffer-stable-across-snapshots" ;;
    *) qemu_vnc_die "unknown case: ${CASE}" ;;
  esac

  qemu_vnc_run_case "${ARCH}" "iso" "build/os-${ARCH}.iso" "${SOCKET_PATH}" "${QMP_SOCKET_PATH}" "${translated_case}" "${LOG_PATH}" "${TIMEOUT_SECS}"
}

run_all_cases() {
  local case_id
  while IFS= read -r case_id; do
    CASE="${case_id}"
    SOCKET_PATH="${REPO_ROOT}/build/vga-memory-${ARCH}-${CASE}.vnc"
    QMP_SOCKET_PATH="${REPO_ROOT}/build/vga-memory-${ARCH}-${CASE}.qmp"
    LOG_PATH="${REPO_ROOT}/build/vga-memory-${ARCH}-${CASE}.log"
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
