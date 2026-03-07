#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CHECK="${2:-}"

die() {
  echo "error: $*" >&2
  exit 2
}

kernel_path() {
  printf 'build/kernel-%s.bin' "${ARCH}"
}

linker_path() {
  printf 'src/arch/%s/linker.ld' "${ARCH}"
}

require_kernel() {
  local kernel
  kernel="$(kernel_path)"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel} (build it with make all arch=${ARCH})"
}

require_linker() {
  local linker
  linker="$(linker_path)"
  [[ -r "${linker}" ]] || die "missing linker script: ${linker}"
}

check_wildcards() {
  local linker
  linker="$(linker_path)"

  grep -qF '*(.rodata .rodata.*)' "${linker}" \
    || die "missing wildcard capture for .rodata.* in ${linker}"
  grep -qF '*(.data .data.*)' "${linker}" \
    || die "missing wildcard capture for .data.* in ${linker}"
  grep -qF '*(.bss .bss.*)' "${linker}" \
    || die "missing wildcard capture for .bss.* in ${linker}"
  grep -qF '*(COMMON)' "${linker}" \
    || die "missing COMMON capture in ${linker}"
}

check_symbol_type() {
  local pattern="$1"
  local expected="$2"
  local kernel
  kernel="$(kernel_path)"

  nm -n "${kernel}" | grep -qE "${pattern}" \
    || die "expected ${expected} proof missing in ${kernel}"
}

check_alloc_allowlist() {
  local kernel
  kernel="$(kernel_path)"

  local unexpected
  unexpected="$(
    readelf -SW "${kernel}" | awk '
      /^[[:space:]]*\[/ {
        name = $3
        flags = $9
        if (index(flags, "A") > 0) {
          allowed = (name == ".boot" || name == ".text" || name == ".rodata" || name == ".data" || name == ".bss")
          if (!allowed) {
            print name
            bad = 1
          }
        }
      }
      END {
        if (bad) {
          exit 1
        }
      }
    ' || true
  )"

  if [[ -n "${unexpected}" ]]; then
    printf 'unexpected allocatable sections in %s:\n%s\n' "${kernel}" "${unexpected}" >&2
    exit 1
  fi
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  case "${CHECK}" in
    wildcards)
      require_linker
      check_wildcards
      ;;
    rodata-subsection)
      require_kernel
      check_symbol_type '[[:space:]]R[[:space:]]+KFS_RODATA_SUBSECTION_MARKER$' \
        'rodata subsection marker'
      ;;
    data-subsection)
      require_kernel
      check_symbol_type '[[:space:]]D[[:space:]]+KFS_DATA_SUBSECTION_MARKER$' \
        'data subsection marker'
      ;;
    bss-subsection)
      require_kernel
      check_symbol_type '[[:space:]][Bb][[:space:]]+KFS_BSS_SUBSECTION_MARKER$' \
        'bss subsection marker'
      ;;
    common-bss)
      require_kernel
      check_symbol_type '[[:space:]][Bb][[:space:]]+KFS_COMMON_BSS_MARKER$' \
        'COMMON-to-bss marker'
      ;;
    alloc-allowlist)
      require_kernel
      check_alloc_allowlist
      ;;
    *)
      die "usage: $0 <arch> {wildcards|rodata-subsection|data-subsection|bss-subsection|common-bss|alloc-allowlist}"
      ;;
  esac
}

main "$@"
