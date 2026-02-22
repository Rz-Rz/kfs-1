#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CHECK="${2:-all}"

die() {
  echo "error: $*" >&2
  exit 2
}

check_file() {
  local kernel="$1"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel}"

  case "${CHECK}" in
    all|langs|interp|dynamic|undef|strings)
      if ! nm -n "${kernel}" | grep -qw 'kfs_rust_marker'; then
        echo "FAIL ${kernel}: Rust marker symbol missing (kfs_rust_marker)"
        echo "hint: the kernel must include the chosen language (Rust) object so M0.2 is proven for ASM+Rust, not ASM-only"
        return 1
      fi
      ;;
  esac

  case "${CHECK}" in
    all|langs)
      if ! nm -n "${kernel}" | grep -qw 'start'; then
        echo "FAIL ${kernel}: ASM entry symbol missing (start)"
        echo "hint: the test kernel must link the ASM boot object and expose the entry symbol"
        return 1
      fi
      ;;
  esac

  case "${CHECK}" in
    all|interp)
      # WP-M0.2-1: no PT_INTERP program header
      if readelf -lW "${kernel}" | grep -qE '^[[:space:]]*INTERP[[:space:]]'; then
        echo "FAIL ${kernel}: PT_INTERP present (dynamic loader required)"
        readelf -lW "${kernel}" | grep -E '^[[:space:]]*INTERP[[:space:]]' || true
        return 1
      fi
      ;;
  esac

  case "${CHECK}" in
    all|dynamic)
      # WP-M0.2-2: no .interp/.dynamic sections
      if readelf -SW "${kernel}" | grep -qE '[[:space:]]\.(interp|dynamic)[[:space:]]'; then
        echo "FAIL ${kernel}: .interp/.dynamic section present (dynamic linking metadata)"
        readelf -SW "${kernel}" | grep -E '[[:space:]]\.(interp|dynamic)[[:space:]]' || true
        return 1
      fi
      ;;
  esac

  case "${CHECK}" in
    all|undef)
      # WP-M0.2-3: no undefined symbols
      if [[ -n "$(nm -u "${kernel}" | head -n 1)" ]]; then
        echo "FAIL ${kernel}: undefined symbols present"
        nm -u "${kernel}" | head -n 50 || true
        return 1
      fi
      ;;
  esac

  case "${CHECK}" in
    all|strings)
      # WP-M0.2-4: no libc/loader strings (heuristic defense-in-depth)
      if strings "${kernel}" | grep -qiE '(glibc|libc\.so|ld-linux)'; then
        echo "FAIL ${kernel}: libc/loader marker strings found"
        strings "${kernel}" | grep -iE '(glibc|libc\.so|ld-linux)' | head -n 20 || true
        return 1
      fi
      ;;
  esac

  echo "PASS ${kernel}"
  return 0
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  case "${CHECK}" in
    all|langs|interp|dynamic|undef|strings) ;;
    *) die "unknown check: ${CHECK} (expected: all|langs|interp|dynamic|undef|strings)" ;;
  esac

  local failures=0

  [[ -r "build/kernel-${ARCH}-test.bin" ]] || die "missing test kernel: build/kernel-${ARCH}-test.bin (build it with make iso-test arch=${ARCH})"
  check_file "build/kernel-${ARCH}-test.bin" || failures=$((failures + 1))

  if [[ "${KFS_M0_2_INCLUDE_RELEASE:-0}" == "1" ]]; then
    [[ -r "build/kernel-${ARCH}.bin" ]] || die "missing release kernel: build/kernel-${ARCH}.bin (build it with make all arch=${ARCH})"
    check_file "build/kernel-${ARCH}.bin" || failures=$((failures + 1))
  fi

  if [[ "${failures}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
