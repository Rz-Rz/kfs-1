#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"
TEST_BIN="build/ut_vga_format"
TEST_SOURCE="tests/host_vga_format.rs"
SOURCE_CRATE="src/kernel/vga.rs"
SOURCE_IMPL="src/kernel/vga/vga_format_impl.rs"

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
  [[ -r "${SOURCE_IMPL}" ]] || die "missing VGA format implementation: ${SOURCE_IMPL}"

  rustc --test -o "${TEST_BIN}" "${TEST_SOURCE}"
  "${TEST_BIN}"

  if ! find_src_pattern '\brender_printf_with_args\b|\bvga_printf_args\b'; then
    echo "FAIL src/tests: missing basic printf implementation"
    exit 1
  fi

  if ! find_src_pattern '%u|%d|%x|%c|%s'; then
    echo "FAIL src/tests: missing expected printf specifier coverage"
    exit 1
  fi

  local kernel_symbols
  kernel_symbols="$(nm -n "${KERNEL}")"
  for symbol in vga_printf vga_printf_args; do
    if ! grep -qE "[[:space:]]T[[:space:]]+${symbol}$" <<<"${kernel_symbols}"; then
      echo "FAIL ${KERNEL}: missing symbol ${symbol}"
      exit 1
    fi
  done

  echo "PASS ${TEST_SOURCE}"
  echo "PASS ${SOURCE_CRATE}"
  echo "PASS ${SOURCE_IMPL}"
  echo "PASS ${KERNEL}"
}

main "$@"
