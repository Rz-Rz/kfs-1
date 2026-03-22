#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
  cat <<'EOF'
interp-pt-interp-present
dynamic-section-present
unresolved-external-symbol
host-runtime-marker-strings
EOF
}

describe_case() {
  case "$1" in
    interp-pt-interp-present) printf '%s\n' "rejects forced .interp / PT_INTERP metadata" ;;
    dynamic-section-present) printf '%s\n' "rejects forced .dynamic metadata" ;;
    unresolved-external-symbol) printf '%s\n' "rejects an unresolved external symbol" ;;
    host-runtime-marker-strings) printf '%s\n' "rejects libc/dynamic-loader marker strings" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

declare -a RELEASE_OBJECT_FILES=()

ensure_release_objects() {
  bash scripts/with-build-lock.sh \
    bash -lc "make clean >/dev/null 2>&1 || true; make -B all arch='${ARCH}' >/dev/null"

  mapfile -t RELEASE_OBJECT_FILES < <(
    find "build/arch/${ARCH}" -type f -name '*.o' ! -path "*/test/*" | sort
  )

  [[ "${#RELEASE_OBJECT_FILES[@]}" -gt 0 ]] || die "no release objects found after build"
}

assert_host_gate_fails() {
  local kernel="$1"
  local gate_case="$2"
  local expected="$3"
  local log="build/m0.2-negative-${CASE}-${gate_case}.log"

  set +e
  KFS_M0_2_KERNEL="${kernel}" \
    KFS_HOST_TEST_DIRECT=1 \
    bash scripts/boot-tests/freestanding-kernel.sh "${ARCH}" "${gate_case}" >"${log}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    echo "FAIL ${CASE}: freestanding gate ${gate_case} unexpectedly passed for ${kernel}" >&2
    cat "${log}" >&2
    exit 1
  fi

  if ! grep -qF "${expected}" "${log}"; then
    echo "FAIL ${CASE}: expected rejection message not found: ${expected}" >&2
    cat "${log}" >&2
    exit 1
  fi
}

write_interp_object() {
  local asm_path="$1"
  cat >"${asm_path}" <<'EOF'
section .interp
  db "/lib/ld-linux.so.2", 0
EOF
}

write_interp_linker_script() {
  local linker_path="$1"
  cat >"${linker_path}" <<'EOF'
ENTRY(start)

PHDRS {
  interp PT_INTERP FLAGS(4);
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
}

SECTIONS {
  . = 1M;
  kernel_start = .;

  .interp : { *(.interp) } :interp :text
  .boot : { *(.multiboot_header) } :text
  .text : { *(.text .text.*) } :text
  .rodata : { *(.rodata .rodata.*) } :text
  .data : { *(.data .data.*) } :data
  .bss : {
    bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    bss_end = .;
  } :data

  kernel_end = .;

  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")
  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")
  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")
}
EOF
}

write_dynamic_object() {
  local asm_path="$1"
  cat >"${asm_path}" <<'EOF'
section .dynamic
  dd 0
  dd 0
EOF
}

write_dynamic_linker_script() {
  local linker_path="$1"
  cat >"${linker_path}" <<'EOF'
ENTRY(start)

PHDRS {
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
  dynamic PT_DYNAMIC FLAGS(6);
}

SECTIONS {
  . = 1M;
  kernel_start = .;

  .boot : { *(.multiboot_header) } :text
  .text : { *(.text .text.*) } :text
  .rodata : { *(.rodata .rodata.*) } :text
  .data : { *(.data .data.*) } :data
  .dynamic : { *(.dynamic) } :data :dynamic
  .bss : {
    bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    bss_end = .;
  } :data

  kernel_end = .;

  ASSERT(kernel_start <= bss_start, "layout symbol order invalid: kernel_start > bss_start")
  ASSERT(bss_start <= bss_end, "layout symbol order invalid: bss_start > bss_end")
  ASSERT(bss_end <= kernel_end, "layout symbol order invalid: bss_end > kernel_end")
}
EOF
}

write_host_runtime_strings_object() {
  local asm_path="$1"
  cat >"${asm_path}" <<'EOF'
section .rodata
  db "glibc", 0
  db "libc.so.6", 0
  db "ld-linux.so.2", 0
EOF
}

write_undefined_symbol_object() {
  local asm_path="$1"
  cat >"${asm_path}" <<'EOF'
global kfs_bad_undefined_call
extern missing_host_symbol

section .text
kfs_bad_undefined_call:
  call missing_host_symbol
  ret
EOF
}

build_object() {
  local asm_path="$1"
  local obj_path="$2"
  nasm -felf32 "${asm_path}" -o "${obj_path}"
}

link_kernel_with_script() {
  local output="$1"
  local linker_path="$2"
  shift 2
  ld -m elf_i386 -n -T "${linker_path}" -o "${output}" "${RELEASE_OBJECT_FILES[@]}" "$@"
}

run_direct_case() {
  ensure_release_objects
  mkdir -p build

  local asm_path linker_path obj_path kernel_path log_path
  asm_path="build/m0.2-negative-${CASE}.asm"
  linker_path="build/m0.2-negative-${CASE}.ld"
  obj_path="build/m0.2-negative-${CASE}.o"
  kernel_path="build/m0.2-negative-${CASE}.bin"
  log_path="build/m0.2-negative-${CASE}.log"

  case "${CASE}" in
    interp-pt-interp-present)
      write_interp_object "${asm_path}"
      write_interp_linker_script "${linker_path}"
      build_object "${asm_path}" "${obj_path}"
      link_kernel_with_script "${kernel_path}" "${linker_path}" "${obj_path}" >"${log_path}" 2>&1
      assert_host_gate_fails "${kernel_path}" 'no-pt-interp-segment' 'PT_INTERP present'
      assert_host_gate_fails "${kernel_path}" 'no-interp-section' '.interp section present'
      ;;
    dynamic-section-present)
      write_dynamic_object "${asm_path}"
      write_dynamic_linker_script "${linker_path}"
      build_object "${asm_path}" "${obj_path}"
      link_kernel_with_script "${kernel_path}" "${linker_path}" "${obj_path}" >"${log_path}" 2>&1
      assert_host_gate_fails "${kernel_path}" 'no-dynamic-section' '.dynamic section present'
      ;;
    unresolved-external-symbol)
      write_undefined_symbol_object "${asm_path}"
      build_object "${asm_path}" "${obj_path}"
      set +e
      ld -m elf_i386 -n -T src/arch/i386/linker.ld -o "${kernel_path}" "${RELEASE_OBJECT_FILES[@]}" "${obj_path}" >"${log_path}" 2>&1
      local rc="$?"
      set -e

      if [[ "${rc}" -eq 0 ]]; then
        echo "FAIL ${CASE}: link unexpectedly succeeded with an unresolved external symbol" >&2
        cat "${log_path}" >&2
        exit 1
      fi

      if ! grep -qE 'undefined reference to .*missing_host_symbol' "${log_path}"; then
        echo "FAIL ${CASE}: expected undefined-reference message not found" >&2
        cat "${log_path}" >&2
        exit 1
      fi
      ;;
    host-runtime-marker-strings)
      write_host_runtime_strings_object "${asm_path}"
      build_object "${asm_path}" "${obj_path}"
      link_kernel_with_script "${kernel_path}" src/arch/i386/linker.ld "${obj_path}" >"${log_path}" 2>&1
      assert_host_gate_fails "${kernel_path}" 'no-libc-strings' 'libc marker strings found'
      assert_host_gate_fails "${kernel_path}" 'no-loader-strings' 'loader marker strings found'
      ;;
    *)
      die "usage: $0 <arch> {interp-pt-interp-present|dynamic-section-present|unresolved-external-symbol|host-runtime-marker-strings}"
      ;;
  esac

  echo "PASS ${CASE}"
}

run_host_case() {
  bash scripts/container.sh run -- \
    bash -lc "KFS_HOST_TEST_DIRECT=1 bash scripts/rejection-tests/freestanding-rejections.sh '${ARCH}' '${CASE}'"
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
