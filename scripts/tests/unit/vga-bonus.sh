#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_vga_bonus.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
  echo "error: $*" >&2
  exit 2
}

list_cases() {
  cat <<'EOF'
host-vga-bonus-normalize-cursor-pos-clamps-out-of-bounds
host-vga-bonus-write-screen-advances-cursor-over-newline
host-vga-bonus-write-screen-scrolls-latest-rows-into-view
EOF
}

describe_case() {
  case "$1" in
    host-vga-bonus-normalize-cursor-pos-clamps-out-of-bounds) printf '%s\n' "host VGA bonus cursor normalization clamps out-of-bounds positions to the last visible cell" ;;
    host-vga-bonus-write-screen-advances-cursor-over-newline) printf '%s\n' "host VGA bonus screen writing advances the cursor over newline" ;;
    host-vga-bonus-write-screen-scrolls-latest-rows-into-view) printf '%s\n' "host VGA bonus screen writing scrolls the latest rows into view" ;;
    *) return 1 ;;
  esac
}

ensure_sources_exist() {
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
}

run_host_tests() {
  local filter="$1"
  local test_bin="build/ut_vga_bonus_${filter%_}"

  run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
  ensure_sources_exist

  case "${CASE}" in
    host-vga-bonus-normalize-cursor-pos-clamps-out-of-bounds)
      run_host_tests 'vga_bonus_normalize_cursor_pos_clamps_out_of_bounds_to_last_visible_cell'
      ;;
    host-vga-bonus-write-screen-advances-cursor-over-newline)
      run_host_tests 'vga_bonus_write_screen_advances_cursor_over_newline'
      ;;
    host-vga-bonus-write-screen-scrolls-latest-rows-into-view)
      run_host_tests 'vga_bonus_write_screen_scrolls_latest_rows_into_view'
      ;;
    *)
      die "usage: $0 <arch> {host-vga-bonus-normalize-cursor-pos-clamps-out-of-bounds|host-vga-bonus-write-screen-advances-cursor-over-newline|host-vga-bonus-write-screen-scrolls-latest-rows-into-view}"
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
