#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"
SOURCE_CRATE="src/kernel/vga.rs"

die() {
  echo "error: $*" >&2
  exit 2
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"
  [[ -r "${SOURCE_CRATE}" ]] || die "missing VGA writer crate: ${SOURCE_CRATE}"

  local source_text
  source_text="$(cat "${SOURCE_CRATE}")"

  if ! grep -qE '0x3D4|0x3D5' <<<"${source_text}"; then
    echo "FAIL ${SOURCE_CRATE}: missing VGA cursor ports 0x3D4/0x3D5"
    exit 1
  fi

  if ! grep -qE 'VGA_CURSOR_HIGH_REGISTER|VGA_CURSOR_LOW_REGISTER' <<<"${source_text}"; then
    echo "FAIL ${SOURCE_CRATE}: missing VGA cursor register selectors (0x0E/0x0F)"
    exit 1
  fi

  if ! grep -qE 'VGA_CURSOR_START_REGISTER|VGA_CURSOR_END_REGISTER' <<<"${source_text}"; then
    echo "FAIL ${SOURCE_CRATE}: missing VGA cursor visibility registers (0x0A/0x0B)"
    exit 1
  fi

  if ! grep -qE '"out dx, al"|core::arch::asm!' <<<"${source_text}"; then
    echo "FAIL ${SOURCE_CRATE}: missing inline port I/O path for hardware cursor"
    exit 1
  fi

  if ! grep -qE 'vga_enable_hardware_cursor\(\)' <<<"${source_text}"; then
    echo "FAIL ${SOURCE_CRATE}: missing explicit hardware cursor enable path"
    exit 1
  fi

  local update_count
  update_count="$(grep -cE 'vga_set_hardware_cursor\(vga_cursor_position\(' <<<"${source_text}")"
  if [[ "${update_count}" -lt 2 ]]; then
    echo "FAIL ${SOURCE_CRATE}: expected hardware cursor updates in both init and putc paths"
    exit 1
  fi

  local disassembly
  disassembly="$(objdump -d "${KERNEL}")"
  if ! grep -qE '\bout\b' <<<"${disassembly}"; then
    echo "FAIL ${KERNEL}: no x86 OUT instructions found (hardware cursor programming path missing in binary)"
    exit 1
  fi

  echo "PASS ${SOURCE_CRATE}"
  echo "PASS ${KERNEL}"
}

main "$@"
