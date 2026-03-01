#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"

die() {
  echo "error: $*" >&2
  exit 2
}

find_src_pattern() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S src >/dev/null
  else
    grep -REn "${pattern}" src >/dev/null
  fi
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"

  if ! find_src_pattern '\bvga_(init|putc|puts)\b'; then
    echo "FAIL src: missing VGA writer API functions (vga_init/vga_putc/vga_puts)"
    exit 1
  fi

  for symbol in vga_init vga_putc vga_puts; do
    if ! nm -n "${KERNEL}" | grep -qE "[[:space:]]T[[:space:]]+${symbol}$"; then
      echo "FAIL ${KERNEL}: missing symbol ${symbol}"
      exit 1
    fi
  done

  if ! objdump -d "${KERNEL}" | grep -qE 'call[[:space:]]+.*<(vga_init|vga_puts)>'; then
    echo "FAIL ${KERNEL}: kmain does not appear to call vga_init/vga_puts"
    exit 1
  fi

  echo "PASS ${KERNEL}"
}

main "$@"
