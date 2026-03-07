#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"
TEST_BIN="build/ut_scroll"
TEST_SOURCE="tests/host_scroll.rs"
SOURCE_CRATE="src/kernel/vga.rs"
SOURCE_IMPL="src/kernel/vga/vga_impl.rs"

die() {
  echo "error: $*" >&2
  exit 2
}

find_src_pattern() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S src tests >/dev/null
  else
    grep -REn "${pattern}" src tests >/dev/null
  fi
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
  [[ -r "${SOURCE_CRATE}" ]] || die "missing VGA writer crate: ${SOURCE_CRATE}"
  [[ -r "${SOURCE_IMPL}" ]] || die "missing VGA cursor implementation: ${SOURCE_IMPL}"

  rustc --test -o "${TEST_BIN}" "${TEST_SOURCE}"
  "${TEST_BIN}"

  if ! find_src_pattern '\bscroll_buffer\b|\bscrolled\b'; then
    echo "FAIL src/tests: missing scroll logic"
    exit 1
  fi

  if ! find_src_pattern 'VGA_HEIGHT - 1|VGA_CELLS - 1'; then
    echo "FAIL src/tests: missing bottom-of-screen scroll coverage"
    exit 1
  fi

  echo "PASS ${TEST_SOURCE}"
  echo "PASS ${SOURCE_CRATE}"
  echo "PASS ${SOURCE_IMPL}"
  echo "PASS ${KERNEL}"
}

main "$@"
