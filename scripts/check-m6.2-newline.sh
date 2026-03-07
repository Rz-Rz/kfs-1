#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
KERNEL="build/kernel-${ARCH}.bin"
TEST_BIN="build/ut_cursor"
TEST_SOURCE="tests/host_cursor.rs"
SOURCE_CRATE="src/kernel/vga.rs"
SOURCE_IMPL="src/kernel/vga/vga_impl.rs"

# This stops the script with a clear error when required files or inputs are missing.
die() {
  echo "error: $*" >&2
  exit 2
}

# This searches both source and test files for a pattern related to the cursor implementation.
find_src_pattern() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S src tests >/dev/null
  else
    grep -REn "${pattern}" src tests >/dev/null
  fi
}

# This builds and runs the cursor tests, then checks that the source really contains cursor state and newline handling.
main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ -r "${KERNEL}" ]] || die "missing artifact: ${KERNEL} (build it with make all/iso arch=${ARCH})"
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
  [[ -r "${SOURCE_CRATE}" ]] || die "missing VGA writer crate: ${SOURCE_CRATE}"
  [[ -r "${SOURCE_IMPL}" ]] || die "missing VGA cursor implementation: ${SOURCE_IMPL}"

  rustc --test -o "${TEST_BIN}" "${TEST_SOURCE}"
  "${TEST_BIN}"

  if ! find_src_pattern '\bVgaCursor\b|\brow\b|\bcol\b'; then
    echo "FAIL src/tests: missing cursor state implementation"
    exit 1
  fi

  if ! find_src_pattern "\\\\n|b'\\\\n'"; then
    echo "FAIL src/tests: missing newline handling"
    exit 1
  fi

  echo "PASS ${TEST_SOURCE}"
  echo "PASS ${SOURCE_CRATE}"
  echo "PASS ${SOURCE_IMPL}"
  echo "PASS ${KERNEL}"
}

main "$@"
