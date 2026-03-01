#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"

die() {
  echo "error: $*" >&2
  exit 2
}

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

