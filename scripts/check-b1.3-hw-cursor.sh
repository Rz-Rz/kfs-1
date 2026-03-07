#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"
SOURCE_WRITER="src/kernel/drivers/vga_text/writer.rs"
SOURCE_PORT="src/kernel/machine/port.rs"

die() {
  echo "error: $*" >&2
  exit 2
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"
  [[ -r "${SOURCE_WRITER}" ]] || die "missing VGA writer source: ${SOURCE_WRITER}"
  [[ -r "${SOURCE_PORT}" ]] || die "missing machine port source: ${SOURCE_PORT}"

  local writer_text
  writer_text="$(cat "${SOURCE_WRITER}")"

  if ! grep -qE '0x3D4|0x3D5' <<<"${writer_text}"; then
    echo "FAIL ${SOURCE_WRITER}: missing VGA cursor ports 0x3D4/0x3D5"
    exit 1
  fi

  if ! grep -qE 'VGA_CURSOR_HIGH_REGISTER|VGA_CURSOR_LOW_REGISTER' <<<"${writer_text}"; then
    echo "FAIL ${SOURCE_WRITER}: missing VGA cursor register selectors (0x0E/0x0F)"
    exit 1
  fi

  if ! grep -qE 'VGA_CURSOR_START_REGISTER|VGA_CURSOR_END_REGISTER' <<<"${writer_text}"; then
    echo "FAIL ${SOURCE_WRITER}: missing VGA cursor visibility registers (0x0A/0x0B)"
    exit 1
  fi

  if ! grep -qE 'write_u8' <<<"${writer_text}"; then
    echo "FAIL ${SOURCE_WRITER}: missing machine-port write path for hardware cursor"
    exit 1
  fi

  if ! grep -qE 'asm!\(' "${SOURCE_PORT}"; then
    echo "FAIL ${SOURCE_PORT}: missing inline port I/O implementation"
    exit 1
  fi

  if ! grep -qE 'ensure_hardware_cursor_enabled\(\)' <<<"${writer_text}"; then
    echo "FAIL ${SOURCE_WRITER}: missing explicit hardware cursor enable path"
    exit 1
  fi

  if ! grep -qE 'vga_set_hardware_cursor\(VGA_CURSOR\)' <<<"${writer_text}"; then
    echo "FAIL ${SOURCE_WRITER}: missing hardware cursor update after writer state changes"
    exit 1
  fi

  local disassembly
  disassembly="$(objdump -d "${KERNEL}")"
  if ! grep -qE '\bout\b' <<<"${disassembly}"; then
    echo "FAIL ${KERNEL}: no x86 OUT instructions found (hardware cursor programming path missing in binary)"
    exit 1
  fi

  echo "PASS ${SOURCE_WRITER}"
  echo "PASS ${SOURCE_PORT}"
  echo "PASS ${KERNEL}"
}

main "$@"
