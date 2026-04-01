#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_vt.rs"
SOURCE_DRIVER="src/kernel/drivers/vga_text/mod.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
  echo "error: $*" >&2
  exit 2
}

list_cases() {
  cat <<'EOF'
host-vga-vt-terminal-buffers-keep-output-and-cursor-state-isolated
host-vga-vt-active-terminal-selection-keeps-each-buffer-intact
source-defines-vga-terminal-bank
source-defines-active-terminal-selector
EOF
}

describe_case() {
  case "$1" in
    host-vga-vt-terminal-buffers-keep-output-and-cursor-state-isolated) printf '%s\n' "host virtual terminals keep retained output and cursor state isolated per terminal" ;;
    host-vga-vt-active-terminal-selection-keeps-each-buffer-intact) printf '%s\n' "host virtual terminals keep each buffer intact when the active terminal changes" ;;
    source-defines-vga-terminal-bank) printf '%s\n' "VGA text driver defines the virtual terminal bank model" ;;
    source-defines-active-terminal-selector) printf '%s\n' "VGA text driver exposes active-terminal selection" ;;
    *) return 1 ;;
  esac
}

ensure_sources_exist() {
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
  [[ -r "${SOURCE_DRIVER}" ]] || die "missing VGA text driver source: ${SOURCE_DRIVER}"
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
}

run_host_tests() {
  local filter="$1"
  local test_bin="build/ut_vga_vt_${filter%_}"

  mkdir -p "$(dirname "${test_bin}")"
  run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
  ensure_sources_exist

  case "${CASE}" in
    host-vga-vt-terminal-buffers-keep-output-and-cursor-state-isolated)
      run_host_tests 'terminal_buffers_keep_output_and_cursor_state_isolated'
      ;;
    host-vga-vt-active-terminal-selection-keeps-each-buffer-intact)
      run_host_tests 'active_terminal_selection_keeps_each_buffer_intact'
      ;;
    source-defines-vga-terminal-bank)
      assert_pattern '\bVgaTerminal\b|\bVgaTerminalBank\b|\bVGA_TEXT_TERMINAL_COUNT\b' 'virtual terminal bank model' "${SOURCE_DRIVER}"
      ;;
    source-defines-active-terminal-selector)
      assert_pattern '\bactive_index\b|\bterminal_mut\b|\bset_active\b|\bvga_text_set_active_terminal\b' 'active terminal selector' "${SOURCE_DRIVER}"
      ;;
    *)
      die "usage: $0 <arch> {host-vga-vt-terminal-buffers-keep-output-and-cursor-state-isolated|host-vga-vt-active-terminal-selection-keeps-each-buffer-intact|source-defines-vga-terminal-bank|source-defines-active-terminal-selector}"
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
