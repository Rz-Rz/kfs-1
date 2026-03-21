#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
CURSOR_TEST_SOURCE="tests/host_cursor.rs"
SCROLL_TEST_SOURCE="tests/host_scroll.rs"
SOURCE_DRIVER="src/kernel/drivers/vga_text/mod.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
  echo "error: $*" >&2
  exit 2
}

list_cases() {
  cat <<'EOF'
host-vga-history-cursor-normalize-cursor-resets-out-of-bounds-to-zero
host-vga-history-cursor-normalize-cursor-pos-clamps-out-of-bounds-positions
host-vga-history-cursor-advances-on-same-row
host-vga-history-cursor-moves-to-next-row-for-newline
host-vga-history-cursor-wraps-last-column-to-next-row
host-vga-history-scrolls-bottom-row-on-newline
host-vga-history-keeps-latest-rows-visible-after-multiple-scrolls
host-vga-history-tail-viewport-top-follows-live-cursor-row
host-vga-history-blit-viewport-restores-older-history-rows
host-vga-history-terminal-tracks-tail-viewport-after-history-scroll
host-vga-history-terminal-backspace-blanks-the-previous-character-cell
source-defines-vga-text-cursor-helpers
source-defines-vga-text-screen-writer
source-defines-vga-history-model
EOF
}

describe_case() {
  case "$1" in
    host-vga-history-cursor-normalize-cursor-resets-out-of-bounds-to-zero) printf '%s\n' "host VGA cursor normalization resets out-of-bounds flat cursors to zero" ;;
    host-vga-history-cursor-normalize-cursor-pos-clamps-out-of-bounds-positions) printf '%s\n' "host VGA cursor normalization clamps out-of-bounds row and column positions" ;;
    host-vga-history-cursor-advances-on-same-row) printf '%s\n' "host VGA writing advances the cursor on the same row for printable bytes" ;;
    host-vga-history-cursor-moves-to-next-row-for-newline) printf '%s\n' "host VGA writing moves to the next row for newline bytes" ;;
    host-vga-history-cursor-wraps-last-column-to-next-row) printf '%s\n' "host VGA writing wraps the last column to the next row" ;;
    host-vga-history-scrolls-bottom-row-on-newline) printf '%s\n' "host VGA screen writing scrolls the bottom row on newline" ;;
    host-vga-history-keeps-latest-rows-visible-after-multiple-scrolls) printf '%s\n' "host VGA screen writing keeps the latest rows visible after repeated scrolls" ;;
    host-vga-history-tail-viewport-top-follows-live-cursor-row) printf '%s\n' "host VGA history computes the live tail viewport top from the logical cursor row" ;;
    host-vga-history-blit-viewport-restores-older-history-rows) printf '%s\n' "host VGA history can blit older retained rows back into the visible viewport" ;;
    host-vga-history-terminal-tracks-tail-viewport-after-history-scroll) printf '%s\n' "host VGA terminal keeps the viewport snapped to the live tail after retained-history scrolling" ;;
    host-vga-history-terminal-backspace-blanks-the-previous-character-cell) printf '%s\n' "host VGA terminal backspace blanks the previous retained-history character cell" ;;
    source-defines-vga-text-cursor-helpers) printf '%s\n' "VGA text driver defines the cursor normalization helpers" ;;
    source-defines-vga-text-screen-writer) printf '%s\n' "VGA text driver defines the screen writer helper" ;;
    source-defines-vga-history-model) printf '%s\n' "VGA text driver defines the retained-history terminal model" ;;
    *) return 1 ;;
  esac
}

ensure_sources_exist() {
  [[ -r "${CURSOR_TEST_SOURCE}" ]] || die "missing host unit test source: ${CURSOR_TEST_SOURCE}"
  [[ -r "${SCROLL_TEST_SOURCE}" ]] || die "missing host unit test source: ${SCROLL_TEST_SOURCE}"
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
  local source="$1"
  local filter="$2"
  local test_bin="build/ut_vga_history_${filter%_}"

  mkdir -p "$(dirname "${test_bin}")"
  run_host_rust_test "${source}" "${test_bin}" "${filter}"
}

run_direct_case() {
  ensure_sources_exist

  case "${CASE}" in
    host-vga-history-cursor-normalize-cursor-resets-out-of-bounds-to-zero)
      run_host_tests "${CURSOR_TEST_SOURCE}" 'vga_text_normalize_cursor_resets_out_of_bounds_cursor_to_zero'
      ;;
    host-vga-history-cursor-normalize-cursor-pos-clamps-out-of-bounds-positions)
      run_host_tests "${CURSOR_TEST_SOURCE}" 'vga_text_normalize_cursor_pos_clamps_out_of_bounds_positions'
      ;;
    host-vga-history-cursor-advances-on-same-row)
      run_host_tests "${CURSOR_TEST_SOURCE}" 'vga_text_write_screen_advances_cursor_on_same_row'
      ;;
    host-vga-history-cursor-moves-to-next-row-for-newline)
      run_host_tests "${CURSOR_TEST_SOURCE}" 'vga_text_write_screen_moves_to_next_row_for_newline'
      ;;
    host-vga-history-cursor-wraps-last-column-to-next-row)
      run_host_tests "${CURSOR_TEST_SOURCE}" 'vga_text_write_screen_wraps_last_column_to_next_row'
      ;;
    host-vga-history-scrolls-bottom-row-on-newline)
      run_host_tests "${SCROLL_TEST_SOURCE}" 'vga_text_write_screen_scrolls_bottom_row_on_newline'
      ;;
    host-vga-history-keeps-latest-rows-visible-after-multiple-scrolls)
      run_host_tests "${SCROLL_TEST_SOURCE}" 'vga_text_write_screen_keeps_latest_rows_visible_after_multiple_scrolls'
      ;;
    host-vga-history-tail-viewport-top-follows-live-cursor-row)
      run_host_tests "${SCROLL_TEST_SOURCE}" 'vga_text_tail_viewport_top_follows_live_cursor_row'
      ;;
    host-vga-history-blit-viewport-restores-older-history-rows)
      run_host_tests "${SCROLL_TEST_SOURCE}" 'vga_text_blit_viewport_restores_older_history_rows'
      ;;
    host-vga-history-terminal-tracks-tail-viewport-after-history-scroll)
      run_host_tests "${SCROLL_TEST_SOURCE}" 'terminal_tracks_tail_viewport_after_history_scroll'
      ;;
    host-vga-history-terminal-backspace-blanks-the-previous-character-cell)
      run_host_tests "${SCROLL_TEST_SOURCE}" 'terminal_backspace_blanks_the_previous_character_cell'
      ;;
    source-defines-vga-text-cursor-helpers)
      assert_pattern '\bvga_text_normalize_cursor\b|\bvga_text_normalize_cursor_pos\b' 'VGA text cursor normalization helpers' "${SOURCE_DRIVER}"
      ;;
    source-defines-vga-text-screen-writer)
      assert_pattern '\bvga_text_write_screen\b' 'VGA text screen writer' "${SOURCE_DRIVER}"
      ;;
    source-defines-vga-history-model)
      assert_pattern '\bVgaHistoryCursor\b|\bVgaTerminal\b|\bVgaTerminalBank\b|\bvga_text_tail_viewport_top\b|\bvga_text_blit_viewport\b' 'VGA history terminal model' "${SOURCE_DRIVER}"
      ;;
    *)
      die "usage: $0 <arch> {host-vga-history-cursor-normalize-cursor-resets-out-of-bounds-to-zero|host-vga-history-cursor-normalize-cursor-pos-clamps-out-of-bounds-positions|host-vga-history-cursor-advances-on-same-row|host-vga-history-cursor-moves-to-next-row-for-newline|host-vga-history-cursor-wraps-last-column-to-next-row|host-vga-history-scrolls-bottom-row-on-newline|host-vga-history-keeps-latest-rows-visible-after-multiple-scrolls|host-vga-history-tail-viewport-top-follows-live-cursor-row|host-vga-history-blit-viewport-restores-older-history-rows|host-vga-history-terminal-tracks-tail-viewport-after-history-scroll|host-vga-history-terminal-backspace-blanks-the-previous-character-cell|source-defines-vga-text-cursor-helpers|source-defines-vga-text-screen-writer|source-defines-vga-history-model}"
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
