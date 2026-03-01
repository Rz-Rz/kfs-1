#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"

die() {
  echo "error: $*" >&2
  exit 2
}

check_kernel() {
  local kernel="$1"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel}"

  local missing=0

  for section in .text .rodata .data .bss; do
    if ! readelf -SW "${kernel}" | grep -qE "[[:space:]]${section}[[:space:]]"; then
      echo "FAIL ${kernel}: missing section ${section}"
      missing=1
    fi
  done

  if ! readelf -SW "${kernel}" | grep -qE '[[:space:]]\.bss[[:space:]].*[[:space:]]NOBITS[[:space:]]'; then
    echo "FAIL ${kernel}: .bss exists but is not NOBITS"
    missing=1
  fi

  if ! nm -n "${kernel}" | grep -qE '[[:space:]]R[[:space:]]+KFS_RODATA_MARKER$'; then
    echo "FAIL ${kernel}: expected read-only marker missing or not in rodata (nm type R): KFS_RODATA_MARKER"
    missing=1
  fi

  if ! nm -n "${kernel}" | grep -qE '[[:space:]]D[[:space:]]+KFS_DATA_MARKER$'; then
    echo "FAIL ${kernel}: expected writable marker missing or not in data (nm type D): KFS_DATA_MARKER"
    missing=1
  fi

  if [[ "${missing}" -ne 0 ]]; then
    echo "hint: Feature M3.2 expects linker output sections (.text/.rodata/.data/.bss) and the Rust canary symbols from src/rust/section_markers.rs"
    return 1
  fi

  echo "PASS ${kernel}"
  return 0
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  local failures=0

  [[ -r "build/kernel-${ARCH}-test.bin" ]] || die "missing test kernel: build/kernel-${ARCH}-test.bin (build it with make iso-test arch=${ARCH})"
  check_kernel "build/kernel-${ARCH}-test.bin" || failures=$((failures + 1))

  if [[ "${KFS_M3_2_INCLUDE_RELEASE:-0}" == "1" ]]; then
    [[ -r "build/kernel-${ARCH}.bin" ]] || die "missing release kernel: build/kernel-${ARCH}.bin (build it with make all arch=${ARCH})"
    check_kernel "build/kernel-${ARCH}.bin" || failures=$((failures + 1))
  fi

  if [[ "${failures}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"

