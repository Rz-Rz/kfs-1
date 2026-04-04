#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_geometry.rs"
TYPE_SOURCE="src/kernel/types/screen.rs"
DRIVER_SOURCE="src/kernel/drivers/vga_text/mod.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
host-vga-geometry-reports-dimensions-and-cell-capacity
host-vga-geometry-clamps-out-of-bounds-positions
host-vga-geometry-cell-index-uses-the-configured-width
host-vga-geometry-tail-viewport-top-tracks-the-configured-height
host-vga-geometry-scroll-rows-up-uses-the-supplied-geometry-width
host-vga-geometry-blit-viewport-uses-the-supplied-geometry-dimensions
source-defines-screen-dimensions-geometry-helpers
source-defines-geometry-aware-scroll-and-blit
EOF
}

describe_case() {
	case "$1" in
	host-vga-geometry-reports-dimensions-and-cell-capacity) printf '%s\n' "host screen geometry reports width, height, and derived capacities" ;;
	host-vga-geometry-clamps-out-of-bounds-positions) printf '%s\n' "host screen geometry clamps out-of-bounds rows and columns" ;;
	host-vga-geometry-cell-index-uses-the-configured-width) printf '%s\n' "host screen geometry computes flat cell indices from the configured width" ;;
	host-vga-geometry-tail-viewport-top-tracks-the-configured-height) printf '%s\n' "host screen geometry computes tail viewport positions from the configured height" ;;
	host-vga-geometry-scroll-rows-up-uses-the-supplied-geometry-width) printf '%s\n' "host VGA row scrolling respects the supplied geometry width" ;;
	host-vga-geometry-blit-viewport-uses-the-supplied-geometry-dimensions) printf '%s\n' "host VGA viewport blits respect the supplied geometry dimensions" ;;
	source-defines-screen-dimensions-geometry-helpers) printf '%s\n' "screen types define reusable geometry helper methods" ;;
	source-defines-geometry-aware-scroll-and-blit) printf '%s\n' "VGA text driver defines geometry-aware scroll and blit helpers" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${TYPE_SOURCE}" ]] || die "missing screen type source: ${TYPE_SOURCE}"
	[[ -r "${DRIVER_SOURCE}" ]] || die "missing VGA driver source: ${DRIVER_SOURCE}"
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
	local test_bin="build/ut_vga_geometry_${filter%_}"

	mkdir -p "$(dirname "${test_bin}")"
	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-vga-geometry-reports-dimensions-and-cell-capacity)
		run_host_tests 'geometry_reports_dimensions_and_cell_capacity'
		;;
	host-vga-geometry-clamps-out-of-bounds-positions)
		run_host_tests 'geometry_clamps_out_of_bounds_positions'
		;;
	host-vga-geometry-cell-index-uses-the-configured-width)
		run_host_tests 'geometry_cell_index_uses_the_configured_width'
		;;
	host-vga-geometry-tail-viewport-top-tracks-the-configured-height)
		run_host_tests 'geometry_tail_viewport_top_tracks_the_configured_height'
		;;
	host-vga-geometry-scroll-rows-up-uses-the-supplied-geometry-width)
		run_host_tests 'scroll_rows_up_uses_the_supplied_geometry_width'
		;;
	host-vga-geometry-blit-viewport-uses-the-supplied-geometry-dimensions)
		run_host_tests 'blit_viewport_uses_the_supplied_geometry_dimensions'
		;;
	source-defines-screen-dimensions-geometry-helpers)
		assert_pattern '\brow_cells\b|\bclamp_row\b|\bclamp_col\b|\bcell_index\b|\blast_row\b|\blast_col\b|\btail_viewport_top\b' 'screen geometry helper methods' "${TYPE_SOURCE}"
		;;
	source-defines-geometry-aware-scroll-and-blit)
		assert_pattern '\bvga_text_scroll_rows_up\b|\bvga_text_blit_viewport\b' 'geometry-aware scroll and blit helpers' "${DRIVER_SOURCE}"
		;;
	*)
		die "usage: $0 <arch> {host-vga-geometry-reports-dimensions-and-cell-capacity|host-vga-geometry-clamps-out-of-bounds-positions|host-vga-geometry-cell-index-uses-the-configured-width|host-vga-geometry-tail-viewport-top-tracks-the-configured-height|host-vga-geometry-scroll-rows-up-uses-the-supplied-geometry-width|host-vga-geometry-blit-viewport-uses-the-supplied-geometry-dimensions|source-defines-screen-dimensions-geometry-helpers|source-defines-geometry-aware-scroll-and-blit}"
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
