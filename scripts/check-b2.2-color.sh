#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"
TEST_BIN="build/ut_color"
TEST_SOURCE="tests/host_color.rs"
SOURCE_CRATE="src/kernel/vga.rs"
SOURCE_IMPL="src/kernel/vga/vga_impl.rs"
SOURCE_PALETTE="src/kernel/vga/vga_palette.rs"

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
  [[ -r "${SOURCE_IMPL}" ]] || die "missing VGA color implementation: ${SOURCE_IMPL}"
  [[ -r "${SOURCE_PALETTE}" ]] || die "missing VGA color palette: ${SOURCE_PALETTE}"

  rustc --test -o "${TEST_BIN}" "${TEST_SOURCE}"
  "${TEST_BIN}"

  if ! find_src_pattern '\bvga_attribute\b|\bVGA_DEFAULT_ATTRIBUTE\b'; then
    echo "FAIL src/tests: missing VGA color attribute model"
    exit 1
  fi

  if ! find_src_pattern '\bvga_set_color\b|\bvga_get_color\b|\bVGA_ATTRIBUTE\b'; then
    echo "FAIL src/tests: missing configurable VGA color API/state"
    exit 1
  fi

  if ! find_src_pattern '\benum VgaColor\b|\bVgaColor::from_index\b|\bVgaColor::ALL\b'; then
    echo "FAIL src/tests: missing enum-based color palette with index mapping"
    exit 1
  fi

  local kernel_symbols
  kernel_symbols="$(nm -n "${KERNEL}")"
  for symbol in vga_set_color vga_get_color; do
    if ! grep -qE "[[:space:]]T[[:space:]]+${symbol}$" <<<"${kernel_symbols}"; then
      echo "FAIL ${KERNEL}: missing symbol ${symbol}"
      exit 1
    fi
  done

  echo "PASS ${TEST_SOURCE}"
  echo "PASS ${SOURCE_CRATE}"
  echo "PASS ${SOURCE_IMPL}"
  echo "PASS ${SOURCE_PALETTE}"
  echo "PASS ${KERNEL}"
}

main "$@"
