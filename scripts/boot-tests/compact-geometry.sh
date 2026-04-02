#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
BOOT_WAIT_SECS="${KFS_VGA_BOOT_WAIT_SECS:-1}"
ISO="build/os-${ARCH}.iso"
LOG="build/compact-geometry-${ARCH}-${CASE}.log"
source "$(dirname "${BASH_SOURCE[0]}")/lib/qemu-monitor.bash"

VGA_TEXT_BUFFER_ADDR=$((0xb8000))
VGA_TEXT_PHYSICAL_WIDTH=80
VGA_TEXT_PHYSICAL_HEIGHT=25
COMPACT_WIDTH=40
COMPACT_HEIGHT=10
COMPACT_ORIGIN_ROW=$(((VGA_TEXT_PHYSICAL_HEIGHT - COMPACT_HEIGHT) / 2))
COMPACT_ORIGIN_COL=$(((VGA_TEXT_PHYSICAL_WIDTH - COMPACT_WIDTH) / 2))
COMPACT_42_ADDR=$((VGA_TEXT_BUFFER_ADDR + (((COMPACT_ORIGIN_ROW * VGA_TEXT_PHYSICAL_WIDTH) + COMPACT_ORIGIN_COL) * 2)))
VGA_TEXT_LABEL_WIDTH=7
VGA_TEXT_LABEL_ADDR=$((VGA_TEXT_BUFFER_ADDR + ((VGA_TEXT_PHYSICAL_WIDTH - VGA_TEXT_LABEL_WIDTH) * 2)))
VGA_TEXT_LABEL_PROBE_BYTES=8

list_cases() {
  cat <<'EOF'
compact-geometry-centers-42-in-physical-vga
compact-geometry-keeps-terminal-label-in-physical-top-right
EOF
}

describe_case() {
  case "$1" in
    compact-geometry-centers-42-in-physical-vga) printf '%s\n' "compact40x10 boot places 42 at the centered physical VGA origin" ;;
    compact-geometry-keeps-terminal-label-in-physical-top-right) printf '%s\n' "compact40x10 boot keeps the active terminal label in the physical top-right overlay region" ;;
    *) return 1 ;;
  esac
}

monitor_script_capture_compact_boot() {
  qemu_monitor_dump_bytes 4 "${COMPACT_42_ADDR}"
  sleep 1
  qemu_monitor_dump_bytes "${VGA_TEXT_LABEL_PROBE_BYTES}" "${VGA_TEXT_LABEL_ADDR}"
  sleep 1
  qemu_monitor_quit
}

run_direct_case() {
  [[ -r "${ISO}" ]] || qemu_monitor_die "missing ISO: ${ISO} (build it with make iso arch=${ARCH})"
  qemu_monitor_capture_release_iso "${ARCH}" "${ISO}" "${LOG}" "${TIMEOUT_SECS}" monitor_script_capture_compact_boot "${BOOT_WAIT_SECS}"

  case "${CASE}" in
    compact-geometry-centers-42-in-physical-vga)
      qemu_monitor_assert_dump_matches "${LOG}" "${COMPACT_42_ADDR}" 1 '0x34[[:space:]]+0x02[[:space:]]+0x32[[:space:]]+0x02'
      ;;
    compact-geometry-keeps-terminal-label-in-physical-top-right)
      qemu_monitor_assert_dump_matches "${LOG}" "${VGA_TEXT_LABEL_ADDR}" 1 '0x20[[:space:]]+0x02[[:space:]]+0x20[[:space:]]+0x02[[:space:]]+0x61[[:space:]]+0x02[[:space:]]+0x6c[[:space:]]+0x02'
      ;;
    *)
      qemu_monitor_die "usage: $0 <arch> {compact-geometry-centers-42-in-physical-vga|compact-geometry-keeps-terminal-label-in-physical-top-right}"
      ;;
  esac
}

run_host_case() {
  bash scripts/with-build-lock.sh \
    bash scripts/container.sh run -- \
    bash -lc "make clean >/dev/null 2>&1 || true; KFS_SCREEN_GEOMETRY_PRESET='compact40x10' make -B iso arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' KFS_VGA_BOOT_WAIT_SECS='${BOOT_WAIT_SECS}' bash scripts/boot-tests/compact-geometry.sh '${ARCH}' '${CASE}'"
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
