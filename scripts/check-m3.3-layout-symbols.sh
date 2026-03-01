#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"

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

check_kernel() {
  local kernel="$1"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel}"

  local missing=0

  for symbol in kernel_start kernel_end bss_start bss_end; do
    if ! nm -n "${kernel}" | grep -qw "${symbol}"; then
      echo "FAIL ${kernel}: missing layout symbol ${symbol}"
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    return 1
  fi

  echo "PASS ${kernel}"
  return 0
}

check_rust_references() {
  local missing=0

  if ! find_src_pattern 'extern[[:space:]]+"C"'; then
    echo "FAIL src: no extern \"C\" layout declaration found"
    return 1
  fi

  for symbol in kernel_start kernel_end bss_start bss_end; do
    if ! find_src_pattern "\\b${symbol}\\b"; then
      echo "FAIL src: missing Rust reference to ${symbol}"
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    return 1
  fi

  echo "PASS src (Rust references layout symbols)"
  return 0
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  local failures=0

  [[ -r "build/kernel-${ARCH}-test.bin" ]] || die "missing test kernel: build/kernel-${ARCH}-test.bin (build it with make iso-test arch=${ARCH})"
  check_kernel "build/kernel-${ARCH}-test.bin" || failures=$((failures + 1))
  check_rust_references || failures=$((failures + 1))

  if [[ "${KFS_M3_3_INCLUDE_RELEASE:-0}" == "1" ]]; then
    [[ -r "build/kernel-${ARCH}.bin" ]] || die "missing release kernel: build/kernel-${ARCH}.bin (build it with make all arch=${ARCH})"
    check_kernel "build/kernel-${ARCH}.bin" || failures=$((failures + 1))
  fi

  if [[ "${failures}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
