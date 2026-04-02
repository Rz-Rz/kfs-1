#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
BOOT_WAIT_SECS="${KFS_UI_BOOT_WAIT_SECS:-1}"
STEP_WAIT_SECS="${KFS_UI_STEP_WAIT_SECS:-0.3}"
ISO="build/os-${ARCH}.iso"
LOG="build/ui-interaction-${ARCH}-${CASE}.log"
source "$(dirname "${BASH_SOURCE[0]}")/lib/qemu-monitor.bash"

VGA_TEXT_BUFFER_ADDR=$((0xb8000))
VGA_TEXT_ROW_WIDTH=80
VGA_TEXT_LABEL_WIDTH=7
VGA_TEXT_LABEL_ADDR=$((VGA_TEXT_BUFFER_ADDR + ((VGA_TEXT_ROW_WIDTH - VGA_TEXT_LABEL_WIDTH) * 2)))
VGA_TEXT_LABEL_PROBE_BYTES=8
VGA_TEXT_START_ADDR="${VGA_TEXT_BUFFER_ADDR}"

list_cases() {
  cat <<'EOF'
f11-creates-terminal-and-label-becomes-beta
f12-destroys-current-terminal-and-label-returns-alpha
terminal-switching-preserves-screen-contents
EOF
}

describe_case() {
  case "$1" in
    f11-creates-terminal-and-label-becomes-beta) printf '%s\n' "QEMU UI interaction maps F11 onto terminal creation and updates the visible label" ;;
    f12-destroys-current-terminal-and-label-returns-alpha) printf '%s\n' "QEMU UI interaction maps F12 onto terminal destruction and returns focus to alpha" ;;
    terminal-switching-preserves-screen-contents) printf '%s\n' "QEMU UI interaction preserves isolated screen contents when switching terminals" ;;
    *) return 1 ;;
  esac
}

ensure_sources_exist() {
  [[ -r "${ISO}" ]] || qemu_monitor_die "missing ISO: ${ISO} (build it with make iso arch=${ARCH})"
}

label_pattern() {
  case "$1" in
    alpha) printf '%s\n' '0x20[[:space:]]+0x02[[:space:]]+0x20[[:space:]]+0x02[[:space:]]+0x61[[:space:]]+0x02[[:space:]]+0x6c[[:space:]]+0x02' ;;
    beta) printf '%s\n' '0x20[[:space:]]+0x02[[:space:]]+0x20[[:space:]]+0x02[[:space:]]+0x20[[:space:]]+0x02[[:space:]]+0x62[[:space:]]+0x02' ;;
    gamma) printf '%s\n' '0x20[[:space:]]+0x02[[:space:]]+0x20[[:space:]]+0x02[[:space:]]+0x67[[:space:]]+0x02[[:space:]]+0x61[[:space:]]+0x02' ;;
    *) qemu_monitor_die "unknown label pattern: $1" ;;
  esac
}

screen_pattern() {
  case "$1" in
    alpha-42) printf '%s\n' '0x34[[:space:]]+0x02[[:space:]]+0x32[[:space:]]+0x02' ;;
    alpha-42c) printf '%s\n' '0x34[[:space:]]+0x02[[:space:]]+0x32[[:space:]]+0x02[[:space:]]+0x63[[:space:]]+0x02' ;;
    beta-b) printf '%s\n' '0x62[[:space:]]+0x02' ;;
    gamma-g) printf '%s\n' '0x67[[:space:]]+0x02' ;;
    *) qemu_monitor_die "unknown screen pattern: $1" ;;
  esac
}

monitor_script_f11_create_beta() {
  qemu_monitor_dump_bytes "${VGA_TEXT_LABEL_PROBE_BYTES}" "${VGA_TEXT_LABEL_ADDR}"
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_sendkey f11
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_dump_bytes "${VGA_TEXT_LABEL_PROBE_BYTES}" "${VGA_TEXT_LABEL_ADDR}"
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_quit
}

monitor_script_f12_destroy_to_alpha() {
  qemu_monitor_sendkey f11
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_dump_bytes "${VGA_TEXT_LABEL_PROBE_BYTES}" "${VGA_TEXT_LABEL_ADDR}"
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_sendkey f12
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_dump_bytes "${VGA_TEXT_LABEL_PROBE_BYTES}" "${VGA_TEXT_LABEL_ADDR}"
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_quit
}

monitor_script_switch_preserves_contents() {
  qemu_monitor_sendkey c
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_dump_bytes 6 "${VGA_TEXT_START_ADDR}"
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_sendkey f11
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_sendkey b
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_dump_bytes 6 "${VGA_TEXT_START_ADDR}"
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_sendkey f1
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_dump_bytes 6 "${VGA_TEXT_START_ADDR}"
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_sendkey f2
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_dump_bytes 6 "${VGA_TEXT_START_ADDR}"
  sleep "${STEP_WAIT_SECS}"
  qemu_monitor_quit
}

run_direct_case() {
  ensure_sources_exist

  case "${CASE}" in
    f11-creates-terminal-and-label-becomes-beta)
      qemu_monitor_capture_release_iso "${ARCH}" "${ISO}" "${LOG}" "${TIMEOUT_SECS}" monitor_script_f11_create_beta "${BOOT_WAIT_SECS}"
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_LABEL_ADDR}" 1 "$(label_pattern alpha)"
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_LABEL_ADDR}" 2 "$(label_pattern beta)"
      ;;
    f12-destroys-current-terminal-and-label-returns-alpha)
      qemu_monitor_capture_release_iso "${ARCH}" "${ISO}" "${LOG}" "${TIMEOUT_SECS}" monitor_script_f12_destroy_to_alpha "${BOOT_WAIT_SECS}"
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_LABEL_ADDR}" 1 "$(label_pattern beta)"
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_LABEL_ADDR}" 2 "$(label_pattern alpha)"
      ;;
    terminal-switching-preserves-screen-contents)
      qemu_monitor_capture_release_iso "${ARCH}" "${ISO}" "${LOG}" "${TIMEOUT_SECS}" monitor_script_switch_preserves_contents "${BOOT_WAIT_SECS}"
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_START_ADDR}" 1 "$(screen_pattern alpha-42c)"
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_START_ADDR}" 2 "$(screen_pattern beta-b)"
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_START_ADDR}" 3 "$(screen_pattern alpha-42c)"
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_START_ADDR}" 4 "$(screen_pattern beta-b)"
      ;;
    *)
      qemu_monitor_die "usage: $0 <arch> {f11-creates-terminal-and-label-becomes-beta|f12-destroys-current-terminal-and-label-returns-alpha|terminal-switching-preserves-screen-contents}"
      ;;
  esac
}

run_host_case() {
  bash scripts/with-build-lock.sh \
    bash scripts/container.sh run -- \
    bash -lc "make clean >/dev/null 2>&1 || true; make -B iso arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' KFS_UI_BOOT_WAIT_SECS='${BOOT_WAIT_SECS}' KFS_UI_STEP_WAIT_SECS='${STEP_WAIT_SECS}' bash scripts/boot-tests/ui-interaction.sh '${ARCH}' '${CASE}'"
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

  describe_case "${CASE}" >/dev/null 2>&1 || qemu_monitor_die "unknown case: ${CASE}"

  if [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  run_direct_case
}

main "$@"
