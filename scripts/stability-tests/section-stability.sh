#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
  cat <<'EOF'
rodata-wildcard-capture
data-wildcard-capture
bss-wildcard-capture
common-wildcard-capture
rodata-subsection-marker
data-subsection-marker
bss-subsection-marker
common-bss-marker
alloc-section-allowlist
EOF
}

describe_case() {
  case "$1" in
    rodata-wildcard-capture) printf '%s\n' "linker script captures .rodata subsections" ;;
    data-wildcard-capture) printf '%s\n' "linker script captures .data subsections" ;;
    bss-wildcard-capture) printf '%s\n' "linker script captures .bss subsections" ;;
    common-wildcard-capture) printf '%s\n' "linker script captures COMMON symbols" ;;
    rodata-subsection-marker) printf '%s\n' "rodata subsection marker still lands in .rodata" ;;
    data-subsection-marker) printf '%s\n' "data subsection marker still lands in .data" ;;
    bss-subsection-marker) printf '%s\n' "bss subsection marker still lands in .bss" ;;
    common-bss-marker) printf '%s\n' "COMMON symbol is folded into .bss" ;;
    alloc-section-allowlist) printf '%s\n' "allocatable sections stay on the allowlist" ;;
    *) return 1 ;;
  esac
}

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

assert_linker_capture() {
  local snippet="$1"
  local label="$2"
  local linker
  linker="$(linker_path)"

  grep -qF "${snippet}" "${linker}" \
    || die "missing ${label} capture in ${linker}"
}

assert_kernel_symbol_type() {
  local pattern="$1"
  local expected="$2"
  local kernel
  kernel="$(kernel_path)"

  nm -n "${kernel}" | grep -qE "${pattern}" \
    || die "expected ${expected} proof missing in ${kernel}"
}

assert_alloc_sections_on_allowlist() {
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

run_direct_case() {
  case "${CASE}" in
    rodata-wildcard-capture)
      require_linker
      assert_linker_capture '*(.rodata .rodata.*)' '.rodata subsection wildcard'
      ;;
    data-wildcard-capture)
      require_linker
      assert_linker_capture '*(.data .data.*)' '.data subsection wildcard'
      ;;
    bss-wildcard-capture)
      require_linker
      assert_linker_capture '*(.bss .bss.*)' '.bss subsection wildcard'
      ;;
    common-wildcard-capture)
      require_linker
      assert_linker_capture '*(COMMON)' 'COMMON'
      ;;
    rodata-subsection-marker)
      require_kernel
      assert_kernel_symbol_type '[[:space:]]R[[:space:]]+KFS_RODATA_SUBSECTION_MARKER$' 'rodata subsection marker'
      ;;
    data-subsection-marker)
      require_kernel
      assert_kernel_symbol_type '[[:space:]]D[[:space:]]+KFS_DATA_SUBSECTION_MARKER$' 'data subsection marker'
      ;;
    bss-subsection-marker)
      require_kernel
      assert_kernel_symbol_type '[[:space:]][Bb][[:space:]]+KFS_BSS_SUBSECTION_MARKER$' 'bss subsection marker'
      ;;
    common-bss-marker)
      require_kernel
      assert_kernel_symbol_type '[[:space:]][Bb][[:space:]]+KFS_COMMON_BSS_MARKER$' 'COMMON-to-bss marker'
      ;;
    alloc-section-allowlist)
      require_kernel
      assert_alloc_sections_on_allowlist
      ;;
    *)
      die "usage: $0 <arch> {rodata-wildcard-capture|data-wildcard-capture|bss-wildcard-capture|common-wildcard-capture|rodata-subsection-marker|data-subsection-marker|bss-subsection-marker|common-bss-marker|alloc-section-allowlist}"
      ;;
  esac
}

run_host_case() {
  case "${CASE}" in
    rodata-wildcard-capture|data-wildcard-capture|bss-wildcard-capture|common-wildcard-capture)
      run_direct_case
      return 0
      ;;
  esac

  bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
    bash -lc "make -B all arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 bash scripts/stability-tests/section-stability.sh '${ARCH}' '${CASE}'"
}

main() {
  if [[ "${ARCH}" == "--list" ]]; then
    list_cases
    return 0
  fi

  if [[ "${ARCH}" == "--description" ]]; then
    describe_case "${CASE}"
    return 0
  fi

  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  if [[ -n "${CASE}" ]] && describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  run_direct_case
}

main "$@"
