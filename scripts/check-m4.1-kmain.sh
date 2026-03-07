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

  if ! nm -n "${KERNEL}" | grep -qE '[[:space:]]T[[:space:]]+kmain$'; then
    echo "FAIL ${KERNEL}: missing Rust entry symbol (expected: T kmain)"
    nm -n "${KERNEL}" | grep -E '\\bkmain\\b' || true
    exit 1
  fi

  if ! objdump -d "${KERNEL}" | grep -qE 'call[[:space:]]+.*<kmain>'; then
    echo "FAIL ${KERNEL}: no call to kmain found in disassembly"
    objdump -d "${KERNEL}" | grep -E '<kmain>' | head -n 20 || true
    exit 1
  fi

  echo "PASS ${KERNEL}"
}

main "$@"
