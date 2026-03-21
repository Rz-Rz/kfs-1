#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
  cat <<'EOF'
bss-before-kernel
bss-end-before-bss-start
kernel-end-before-bss-end
EOF
}

describe_case() {
  case "$1" in
    bss-before-kernel) printf '%s\n' 'rejects bss_start before kernel_start' ;;
    bss-end-before-bss-start) printf '%s\n' 'rejects bss_end before bss_start' ;;
    kernel-end-before-bss-end) printf '%s\n' 'rejects kernel_end before bss_end' ;;
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
    bss-before-kernel)
      cat >"${path}" <<'EOF'
ENTRY(start)

SECTIONS {
  . = 1M;
  bss_start = .;
  kernel_start = . + 0x10;

  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : {
    *(.bss .bss.*)
    *(COMMON)
    bss_end = .;
  }

  kernel_end = .;

  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")
  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")
  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")
}
EOF
      ;;
    bss-end-before-bss-start)
      cat >"${path}" <<'EOF'
ENTRY(start)

SECTIONS {
  . = 1M;
  kernel_start = .;

  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : {
    bss_end = .;
    *(.bss .bss.*)
    *(COMMON)
    bss_start = .;
  }

  kernel_end = .;

  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")
  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")
  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")
}
EOF
      ;;
    kernel-end-before-bss-end)
      cat >"${path}" <<'EOF'
ENTRY(start)

SECTIONS {
  . = 1M;
  kernel_start = .;

  .boot : { *(.multiboot_header) }
  .text : { *(.text .text.*) }
  .rodata : { *(.rodata .rodata.*) }
  .data : { *(.data .data.*) }
  .bss : {
    bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    bss_end = .;
  }

  kernel_end = bss_start;

  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")
  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")
  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")
}
EOF
      ;;
    *)
      die "usage: $0 <arch> {bss-before-kernel|bss-end-before-bss-start|kernel-end-before-bss-end}"
      ;;
  esac
}

expected_message() {
  case "${CASE}" in
    bss-before-kernel) printf '%s' 'layout symbol order invalid: kernel_start > bss_start' ;;
    bss-end-before-bss-start) printf '%s' 'layout symbol order invalid: bss_start > bss_end' ;;
    kernel-end-before-bss-end) printf '%s' 'layout symbol order invalid: bss_end > kernel_end' ;;
    *) die "unexpected case: ${CASE}" ;;
  esac
}

run_direct_case() {
  local linker="build/m3.3-negative-${CASE}.ld"
  local log="build/m3.3-negative-${CASE}.log"
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
  bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
    bash -lc "KFS_HOST_TEST_DIRECT=1 bash scripts/rejection-tests/layout-symbol-rejections.sh '${ARCH}' '${CASE}'"
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
