#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"

# This prints an error and exits when the expected build artifact or symbol is missing.
die() {
  echo "error: $*" >&2
  exit 2
}

# This proves the kernel exports `kmain` and that the boot code really calls it.
main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"

  local kernel_symbols
  kernel_symbols="$(nm -n "${KERNEL}")"
  if ! grep -qE '[[:space:]]T[[:space:]]+kmain$' <<<"${kernel_symbols}"; then
    echo "FAIL ${KERNEL}: missing Rust entry symbol (expected: T kmain)"
    grep -E '\\bkmain\\b' <<<"${kernel_symbols}" || true
    exit 1
  fi

  local disassembly
  disassembly="$(objdump -d "${KERNEL}")"
  if ! grep -qE 'call[[:space:]]+.*<kmain>' <<<"${disassembly}"; then
    echo "FAIL ${KERNEL}: no call to kmain found in disassembly"
    grep -E '<kmain>' <<<"${disassembly}" | head -n 20 || true
    exit 1
  fi

  echo "PASS ${KERNEL}"
}

main "$@"
