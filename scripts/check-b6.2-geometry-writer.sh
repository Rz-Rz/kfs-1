#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
TEST_BIN="build/ut_geometry_writer"
TEST_SOURCE="tests/host_geometry_writer.rs"
SOURCE_CRATE="src/kernel/vga.rs"
SOURCE_IMPL="src/kernel/vga/vga_impl.rs"

die() {
  echo "error: $*" >&2
  exit 2
}

main() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
  [[ -r "${SOURCE_CRATE}" ]] || die "missing VGA service source: ${SOURCE_CRATE}"
  [[ -r "${SOURCE_IMPL}" ]] || die "missing VGA writer implementation: ${SOURCE_IMPL}"

  rustc --test -o "${TEST_BIN}" "${TEST_SOURCE}"
  "${TEST_BIN}"

  if ! rg -n '\b(move_to|put_byte|backspace|reset)_with_geometry\b|\btail_viewport_top_with_geometry\b' -S "${SOURCE_IMPL}" >/dev/null; then
    echo "FAIL ${SOURCE_IMPL}: missing geometry-aware writer operations"
    exit 1
  fi

  if ! rg -n 'VGA_GEOMETRY|ScreenGeometry::new\(4, 3\)' -S "${TEST_SOURCE}" >/dev/null; then
    echo "FAIL ${TEST_SOURCE}: missing two-geometry coverage"
    exit 1
  fi

  echo "PASS ${TEST_SOURCE}"
  echo "PASS ${SOURCE_CRATE}"
  echo "PASS ${SOURCE_IMPL}"
}

main "$@"
