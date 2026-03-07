#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

die() {
  echo "error: $*" >&2
  exit 2
}

write_linker_script() {
  local path="$1"

  case "${CASE}" in
    text-missing)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  .boot : { *(.multiboot_header) }
  .rodata : { *(.text .text.*) *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
}
EOF
      ;;
    text-wrong-type)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  .boot : { *(.multiboot_header) }
  .text (NOLOAD) : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
}
EOF
      ;;
    rodata-missing)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
}
EOF
      ;;
    rodata-wrong-type)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata (NOLOAD) : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
}
EOF
      ;;
    data-missing)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
}
EOF
      ;;
    data-wrong-type)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data (NOLOAD) : { *(.data .data.*) }
  .bss : { *(.bss .bss.*) *(COMMON) }
}
EOF
      ;;
    bss-missing)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) *(.bss .bss.*) *(COMMON) }
}
EOF
      ;;
    bss-wrong-type)
      cat >"${path}" <<'EOF'
ENTRY(start)
SECTIONS {
  . = 1M;
  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : { BYTE(0); *(.bss .bss.*) *(COMMON) }
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

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  local linker="build/m3.2-negative-${CASE}.ld"
  local log="build/m3.2-negative-${CASE}.log"
  local expected
  expected="$(expected_message)"

  make clean >/dev/null 2>&1 || true
  mkdir -p build
  write_linker_script "${linker}"

  if make -B all arch="${ARCH}" linker_script="${linker}" >"${log}" 2>&1; then
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

main "$@"
