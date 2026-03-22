#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_vga_writer.rs"
DRIVER_SOURCE="src/kernel/drivers/vga_text/mod.rs"
CONSOLE_SOURCE="src/kernel/services/console.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

list_cases() {
  cat <<'EOF'
host-vga-writer-sequential-writes
host-vga-writer-preserves-unwritten-cells
host-vga-writer-wraps-at-buffer-end
host-vga-writer-continues-from-cursor
host-vga-writer-handles-empty-buffer
rust-defines-vga-writer-model
services-console-keeps-writer-state
EOF
}

describe_case() {
  case "$1" in
    host-vga-writer-sequential-writes) printf '%s\n' "host VGA writer writes bytes in sequence" ;;
    host-vga-writer-preserves-unwritten-cells) printf '%s\n' "host VGA writer preserves unwritten cells" ;;
    host-vga-writer-wraps-at-buffer-end) printf '%s\n' "host VGA writer wraps at the end of the buffer" ;;
    host-vga-writer-continues-from-cursor) printf '%s\n' "host VGA writer continues from the provided cursor" ;;
    host-vga-writer-handles-empty-buffer) printf '%s\n' "host VGA writer handles an empty buffer safely" ;;
    rust-defines-vga-writer-model) printf '%s\n' "Rust defines the shared VGA writer model helper" ;;
    services-console-keeps-writer-state) printf '%s\n' "services console does not reset VGA writer state on each call" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

ensure_sources_exist() {
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
  [[ -r "${DRIVER_SOURCE}" ]] || die "missing VGA driver source: ${DRIVER_SOURCE}"
  [[ -r "${CONSOLE_SOURCE}" ]] || die "missing services console source: ${CONSOLE_SOURCE}"
}

find_pattern() {
  local pattern="$1"
  shift

  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S "$@" >/dev/null
  else
    grep -En "${pattern}" "$@" >/dev/null
  fi
}

assert_pattern() {
  local pattern="$1"
  local label="$2"
  shift 2

  if ! find_pattern "${pattern}" "$@"; then
    echo "FAIL src: missing ${label}"
    return 1
  fi

  echo "PASS src: ${label}"
  return 0
}

assert_no_pattern() {
  local pattern="$1"
  local label="$2"
  shift 2

  if find_pattern "${pattern}" "$@"; then
    echo "FAIL src: found ${label}"
    if command -v rg >/dev/null 2>&1; then
      rg -n "${pattern}" -S "$@" || true
    else
      grep -En "${pattern}" "$@" || true
    fi
    return 1
  fi

  echo "PASS src: ${label}"
  return 0
}

run_host_tests() {
  local filter="$1"
  local test_bin="build/ut_vga_writer_${filter%_}"

  run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
  ensure_sources_exist

  case "${CASE}" in
    host-vga-writer-sequential-writes)
      run_host_tests 'vga_writer_writes_bytes_in_sequence'
      ;;
    host-vga-writer-preserves-unwritten-cells)
      run_host_tests 'vga_writer_preserves_unwritten_cells'
      ;;
    host-vga-writer-wraps-at-buffer-end)
      run_host_tests 'vga_writer_wraps_at_buffer_end'
      ;;
    host-vga-writer-continues-from-cursor)
      run_host_tests 'vga_writer_continues_from_existing_cursor'
      ;;
    host-vga-writer-handles-empty-buffer)
      run_host_tests 'vga_writer_handles_empty_buffer'
      ;;
    rust-defines-vga-writer-model)
      assert_pattern '\bfn[[:space:]]+vga_text_write_cells\b' 'vga_text_write_cells definition' "${DRIVER_SOURCE}"
      ;;
    services-console-keeps-writer-state)
      assert_no_pattern '\bvga_text::init\s*\(' 'console-side VGA writer reset' "${CONSOLE_SOURCE}"
      ;;
    *)
      die "usage: $0 <arch> {host-vga-writer-sequential-writes|host-vga-writer-preserves-unwritten-cells|host-vga-writer-wraps-at-buffer-end|host-vga-writer-continues-from-cursor|host-vga-writer-handles-empty-buffer|rust-defines-vga-writer-model|services-console-keeps-writer-state}"
      ;;
  esac
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
  run_direct_case
}

main "$@"
