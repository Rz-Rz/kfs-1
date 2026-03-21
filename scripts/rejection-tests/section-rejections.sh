#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
  cat <<'EOF'
text-missing
text-wrong-type
rodata-missing
rodata-wrong-type
data-missing
data-wrong-type
bss-missing
bss-wrong-type
EOF
}

describe_case() {
  case "$1" in
    text-missing) printf '%s\n' "rejects missing .text section" ;;
    text-wrong-type) printf '%s\n' "rejects .text with wrong section type" ;;
    rodata-missing) printf '%s\n' "rejects missing .rodata section" ;;
    rodata-wrong-type) printf '%s\n' "rejects .rodata with wrong section type" ;;
    data-missing) printf '%s\n' "rejects missing .data section" ;;
    data-wrong-type) printf '%s\n' "rejects .data with wrong section type" ;;
    bss-missing) printf '%s\n' "rejects missing .bss section" ;;
    bss-wrong-type) printf '%s\n' "rejects .bss with wrong section type" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

write_invalid_linker_script() {
  local path="$1"

  case "${CASE}" in
    text-missing)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  kernel_start = .;
  .boot : { *(.multiboot_header) }
  .rodata : { *(.text .text.*) *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
  bss_start = .;
  bss_end = .;
  kernel_end = .;
}
EOF
      ;;
    text-wrong-type)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  kernel_start = .;
  .boot : { *(.multiboot_header) }
  .text (NOLOAD) : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
  bss_start = .;
  bss_end = .;
  kernel_end = .;
}
EOF
      ;;
    rodata-missing)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  kernel_start = .;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
  bss_start = .;
  bss_end = .;
  kernel_end = .;
}
EOF
      ;;
    rodata-wrong-type)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  kernel_start = .;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata (NOLOAD) : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
  bss_start = .;
  bss_end = .;
  kernel_end = .;
}
EOF
      ;;
    data-missing)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  kernel_start = .;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
  bss_start = .;
  bss_end = .;
  kernel_end = .;
}
EOF
      ;;
    data-wrong-type)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  kernel_start = .;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data (NOLOAD) : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
  bss_start = .;
  bss_end = .;
  kernel_end = .;
}
EOF
      ;;
    bss-missing)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  kernel_start = .;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) *(.bss .bss.*) *(COMMON) }
  bss_start = .;
  bss_end = .;
  kernel_end = .;
}
EOF
      ;;
    bss-wrong-type)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  kernel_start = .;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { BYTE(0); *(.bss .bss.*) *(COMMON) }
  bss_start = .;
  bss_end = .;
  kernel_end = .;
}
EOF
      ;;
    *)
      die "usage: $0 <arch> {text-missing|text-wrong-type|rodata-missing|rodata-wrong-type|data-missing|data-wrong-type|bss-missing|bss-wrong-type}"
      ;;
  esac
}

expected_message() {
  case "${CASE}" in
    text-missing) printf '%s' 'missing section .text' ;;
    text-wrong-type) printf '%s' '.text exists but is not PROGBITS' ;;
    rodata-missing) printf '%s' 'missing section .rodata' ;;
    rodata-wrong-type) printf '%s' '.rodata exists but is not PROGBITS' ;;
    data-missing) printf '%s' 'missing section .data' ;;
    data-wrong-type) printf '%s' '.data exists but is not PROGBITS' ;;
    bss-missing) printf '%s' 'missing section .bss' ;;
    bss-wrong-type) printf '%s' '.bss exists but is not NOBITS' ;;
    *) die "unexpected case: ${CASE}" ;;
  esac
}

run_direct_case() {
  local linker="build/m3.2-negative-${CASE}.ld"
  local log="build/m3.2-negative-${CASE}.log"
  local expected
  expected="$(expected_message)"

  bash scripts/with-build-lock.sh make clean >/dev/null 2>&1 || true
  mkdir -p build
  write_invalid_linker_script "${linker}"

  if bash scripts/with-build-lock.sh make -B all arch="${ARCH}" linker_script="${linker}" >"${log}" 2>&1; then
    echo "FAIL ${CASE}: wrong linker script unexpectedly passed the build gate" >&2
    cat "${log}" >&2
    exit 1
  fi

  if ! grep -qF "${expected}" "${log}"; then
    echo "FAIL ${CASE}: expected rejection message not found: ${expected}" >&2
    cat "${log}" >&2
    exit 1
  fi

  echo "PASS ${CASE}"
}

run_host_case() {
  bash scripts/container.sh run -- \
    bash -lc "KFS_HOST_TEST_DIRECT=1 bash scripts/rejection-tests/section-rejections.sh '${ARCH}' '${CASE}'"
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
