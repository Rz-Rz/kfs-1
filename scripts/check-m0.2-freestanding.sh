#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"

die() {
  echo "error: $*" >&2
  exit 2
}

check_file() {
  local kernel="$1"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel}"

  # WP-M0.2-1: no PT_INTERP program header
  if readelf -lW "${kernel}" | grep -qE '^[[:space:]]*INTERP[[:space:]]'; then
    echo "M0.2 FAIL ${kernel}: PT_INTERP present (dynamic loader required)"
    readelf -lW "${kernel}" | grep -E '^[[:space:]]*INTERP[[:space:]]' || true
    return 1
  fi

  # WP-M0.2-2: no .interp/.dynamic sections
  if readelf -SW "${kernel}" | grep -qE '[[:space:]]\.(interp|dynamic)[[:space:]]'; then
    echo "M0.2 FAIL ${kernel}: .interp/.dynamic section present (dynamic linking metadata)"
    readelf -SW "${kernel}" | grep -E '[[:space:]]\.(interp|dynamic)[[:space:]]' || true
    return 1
  fi

  # WP-M0.2-3: no undefined symbols
  if [[ -n "$(nm -u "${kernel}" | head -n 1)" ]]; then
    echo "M0.2 FAIL ${kernel}: undefined symbols present"
    nm -u "${kernel}" | head -n 50 || true
    return 1
  fi

  # WP-M0.2-4: no libc/loader strings (heuristic defense-in-depth)
  if strings "${kernel}" | grep -qiE '(glibc|libc\.so|ld-linux)'; then
    echo "M0.2 FAIL ${kernel}: libc/loader marker strings found"
    strings "${kernel}" | grep -iE '(glibc|libc\.so|ld-linux)' | head -n 20 || true
    return 1
  fi

  echo "M0.2 PASS ${kernel}"
  return 0
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  local failures=0

  if [[ -r "build/kernel-${ARCH}.bin" ]]; then
    check_file "build/kernel-${ARCH}.bin" || failures=$((failures + 1))
  else
    echo "M0.2 SKIP build/kernel-${ARCH}.bin (not present)"
  fi

  if [[ -r "build/kernel-${ARCH}-test.bin" ]]; then
    check_file "build/kernel-${ARCH}-test.bin" || failures=$((failures + 1))
  else
    echo "M0.2 SKIP build/kernel-${ARCH}-test.bin (not present)"
  fi

  if [[ "${failures}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"

