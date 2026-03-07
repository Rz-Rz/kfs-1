#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
VERBOSE="${KFS_VERBOSE:-0}"

TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
TEST_PASS_RC="${TEST_PASS_RC:-33}"
TEST_FAIL_RC="${TEST_FAIL_RC:-35}"
KFS_TEST_FORCE_FAIL="${KFS_TEST_FORCE_FAIL:-0}"

die() {
  echo "error: $*" >&2
  exit 2
}

is_tty() {
  [[ -t 1 ]]
}

want_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ "${KFS_COLOR:-}" == "1" ]] && return 0
  is_tty
}

color() {
  local code="$1"
  if want_color; then
    printf '\033[%sm' "${code}"
  fi
}

reset_color() {
  if want_color; then
    printf '\033[0m'
  fi
}

hr() {
  printf '%s\n' "============================================================"
}

banner() {
  local title="$1"
  hr
  color "1;34"
  printf '%s\n' "${title}"
  reset_color
  hr
}

info() {
  color "2"
  printf '%s' "$*"
  reset_color
}

pass() {
  color "32"
  printf '%s' "PASS"
  reset_color
}

fail() {
  color "31"
  printf '%s' "FAIL"
  reset_color
}

indent() {
  sed 's/^/  /'
}

run_item() {
  local idx="$1"
  local total="$2"
  local title="$3"
  shift 3

  color "1;34"
  printf '[%s/%s] %s ' "${idx}" "${total}" "${title}"
  reset_color

  local log
  log="$(mktemp -t kfs-test.XXXXXX)"
  set +e
  "$@" >"${log}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    pass
    printf '\n'
    if [[ "${VERBOSE}" == "1" ]]; then
      cat "${log}" | indent
    fi
    rm -f "${log}"
    return 0
  fi

  fail
  printf '\n'
  cat "${log}" | indent
  rm -f "${log}"
  return "${rc}"
}

run_item_inline() {
  local idx="$1"
  local total="$2"
  local title="$3"
  shift 3

  color "1;34"
  printf '[%s/%s] %s ' "${idx}" "${total}" "${title}"
  reset_color

  local log rc
  log="$(mktemp -t kfs-test.XXXXXX)"
  set +e
  "$@" >"${log}" 2>&1
  rc="$?"
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    pass
    printf '\n'
    if [[ "${VERBOSE}" == "1" ]]; then
      cat "${log}" | indent
    fi
    rm -f "${log}"
    return 0
  fi

  fail
  printf '\n'
  cat "${log}" | indent
  rm -f "${log}"
  return "${rc}"
}

[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

export KFS_CONTAINER_TTY=0
is_tty && export KFS_CONTAINER_TTY=1

banner "KFS TESTS"
info "arch: ${ARCH}"
printf '\n'

color "1;34"; printf '%s\n' "SETUP"; reset_color
run_item 1 2 "Rebuild the container toolchain image" \
  env KFS_FORCE_IMAGE_BUILD=1 bash scripts/container.sh build-image

run_item 2 2 "Verify tools exist" \
  bash scripts/container.sh env-check

printf '\n'
color "1;34"; printf '%s\n' "TESTS"; reset_color
run_item 1 31 "release ISO is bootable" \
  bash scripts/container.sh run -- \
    bash -lc "make -B iso arch='${ARCH}' >/dev/null && test -f build/os-${ARCH}.iso && test \$(wc -c < build/os-${ARCH}.iso) -le 10485760 && file build/os-${ARCH}.iso | grep -q 'ISO 9660'"

run_item 2 31 "release IMG is bootable" \
  bash scripts/container.sh run -- \
    bash -lc "make -B img arch='${ARCH}' >/dev/null && test -f build/os-${ARCH}.img && test \$(wc -c < build/os-${ARCH}.img) -le 10485760 && file build/os-${ARCH}.img | grep -q 'ISO 9660' && cmp -s build/os-${ARCH}.iso build/os-${ARCH}.img"

run_item 3 31 "linker script defines .rodata/.data/.bss" \
  bash scripts/container.sh run -- \
    bash -lc "grep -nE '^\\s*\\.(rodata|data|bss)\\b' src/arch/${ARCH}/linker.ld >/dev/null"

run_item 4 31 "release kernel contains .text/.rodata/.data/.bss" \
  bash scripts/container.sh run -- \
    bash -lc "KERNEL='build/kernel-${ARCH}.bin'; readelf -SW \"\${KERNEL}\" | grep -qE '\\.(text|rodata|data|bss)\\b'"

run_item 5 31 "release rodata marker lands in .rodata" \
  bash scripts/container.sh run -- \
    bash -lc "nm -n 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]R[[:space:]]+KFS_RODATA_MARKER$'"

run_item 6 31 "release data marker lands in .data" \
  bash scripts/container.sh run -- \
    bash -lc "nm -n 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]D[[:space:]]+KFS_DATA_MARKER$'"

run_item 7 31 "release bss marker lands in .bss" \
  bash scripts/container.sh run -- \
    bash -lc "nm -n 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]][Bb][[:space:]]+KFS_BSS_MARKER$'"

run_item 8 31 "release .bss is emitted as NOBITS" \
  bash scripts/container.sh run -- \
    bash -lc "readelf -SW 'build/kernel-${ARCH}.bin' | grep -qE '\\.bss\\b.*NOBITS'"

printf '\n'
color "1;34"; printf '%s\n' "STABILITY TESTS"; reset_color

# Future compiler output rarely stops at bare section names. Compilers and assemblers often emit
# subsection names such as .rodata.foo, .data.rel.local, or .bss.something. If the linker script
# only matches the base names and forgets COMMON, those future inputs become orphans or land wrong.
# This check proves the script keeps the wildcard and COMMON rules that make later growth safe.
run_item 9 31 "linker script captures subsections and COMMON" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-stability.sh '${ARCH}' wildcards"

# This canary is deliberately emitted into an input subsection named .rodata.kfs_test instead of
# plain .rodata. If it still shows up as an R symbol in the final ELF, the wildcard rule
# *(.rodata .rodata.*) is doing real work and future read-only subsections will stay correct.
run_item 10 31 "rodata subsection marker still lands in .rodata" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-stability.sh '${ARCH}' rodata-subsection"

# This canary is emitted into .data.kfs_test. A PASS here proves that initialized writable globals
# do not have to use the exact bare .data name; subsection variants are still folded into output
# .data rather than becoming orphan sections or drifting into a wrong region.
run_item 11 31 "data subsection marker still lands in .data" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-stability.sh '${ARCH}' data-subsection"

# This canary is emitted into .bss.kfs_test. A PASS proves that zero-init subsection variants still
# become true BSS symbols in the linked kernel, which matters for later globals, buffers, and
# statics that the compiler may name with .bss.* subsections.
run_item 12 31 "bss subsection marker still lands in .bss" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-stability.sh '${ARCH}' bss-subsection"

# COMMON is an older zero-init storage class produced by some assemblers/toolchains. Without
# *(COMMON) in the linker script, these symbols may not be folded into .bss at all. This check
# proves the linker still handles that legacy-but-real input form.
run_item 13 31 "COMMON symbol is folded into .bss" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-stability.sh '${ARCH}' common-bss"

# This is the broad regression guard. It inspects allocatable sections in the final ELF and fails
# if a new loadable/runtime section appears outside the small allowlist we expect. That catches
# surprises like .eh_frame before they silently become part of the shipped kernel image.
run_item 14 31 "allocatable sections stay on the allowlist" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-stability.sh '${ARCH}' alloc-allowlist"

printf '\n'
color "1;34"; printf '%s\n' "REJECTION TESTS"; reset_color

# These tests compile the real kernel with intentionally bad linker scripts and prove the
# post-link M3.2 gate rejects the build for the expected reason instead of silently shipping
# a malformed ELF.
run_item 15 31 "rejects missing .text section" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-rejections.sh '${ARCH}' text-missing"

# This proves the gate catches a present-but-wrong ELF type for the code section.
run_item 16 31 "rejects .text with wrong section type" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-rejections.sh '${ARCH}' text-wrong-type"

# This proves the gate rejects linker scripts that erase the dedicated read-only data section.
run_item 17 31 "rejects missing .rodata section" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-rejections.sh '${ARCH}' rodata-missing"

# This proves the gate catches a present-but-wrong ELF type for read-only data.
run_item 18 31 "rejects .rodata with wrong section type" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-rejections.sh '${ARCH}' rodata-wrong-type"

# This proves the gate rejects linker scripts that erase the dedicated initialized data section.
run_item 19 31 "rejects missing .data section" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-rejections.sh '${ARCH}' data-missing"

# This proves the gate catches a present-but-wrong ELF type for initialized writable data.
run_item 20 31 "rejects .data with wrong section type" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-rejections.sh '${ARCH}' data-wrong-type"

# This proves the gate rejects linker scripts that erase the dedicated BSS section entirely.
run_item 21 31 "rejects missing .bss section" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-rejections.sh '${ARCH}' bss-missing"

# This proves the gate catches a present-but-wrong ELF type for zero-init storage.
run_item 22 31 "rejects .bss with wrong section type" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-rejections.sh '${ARCH}' bss-wrong-type"

printf '\n'
color "1;34"; printf '%s\n' "BOOT TESTS"; reset_color
run_item 23 31 "Build test ISO" \
  bash scripts/container.sh run -- \
    bash -lc "make -B iso-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL}' >/dev/null"

run_item 24 31 "kernel includes ASM+Rust (symbol gate)" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' langs"

run_item 25 31 "no host libs (ELF checks): no PT_INTERP" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' interp"

run_item 26 31 "no host libs (ELF checks): no .interp/.dynamic" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' dynamic"

run_item 27 31 "no host libs (ELF checks): no undefined symbols" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' undef"

run_item 28 31 "no host libs (ELF checks): no libc/loader strings" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' strings"

run_item_inline 29 31 "GRUB boots test ISO" \
  bash scripts/container.sh run -- env \
    TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS}" \
    TEST_PASS_RC="${TEST_PASS_RC}" \
    TEST_FAIL_RC="${TEST_FAIL_RC}" \
    KFS_TEST_FORCE_FAIL="${KFS_TEST_FORCE_FAIL}" \
    bash scripts/test-qemu.sh "${ARCH}"

run_item 30 31 "Build test IMG artifact" \
  bash scripts/container.sh run -- \
    bash -lc "make -B img-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL}' >/dev/null"

run_item_inline 31 31 "GRUB boots test IMG" \
  bash scripts/container.sh run -- env \
    TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS}" \
    TEST_PASS_RC="${TEST_PASS_RC}" \
    TEST_FAIL_RC="${TEST_FAIL_RC}" \
    KFS_TEST_FORCE_FAIL="${KFS_TEST_FORCE_FAIL}" \
    bash scripts/test-qemu.sh "${ARCH}" drive

printf '\n'
pass
printf ' %s\n' "SUMMARY PASS"
