#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_geometry_writer.rs"
TYPE_SOURCE="src/kernel/types/screen.rs"
DRIVER_SOURCE="src/kernel/drivers/vga_text/mod.rs"
WRITER_SOURCE="src/kernel/drivers/vga_text/writer.rs"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
host-vga-geometry-writer-centers-compact-rows-without-duplicate-cells
host-vga-geometry-writer-computes-centered-render-origin
source-defines-physical-vga-dimensions
source-defines-logical-to-physical-renderer
source-writer-centers-logical-buffer-inside-physical-vga
EOF
}

describe_case() {
	case "$1" in
	host-vga-geometry-writer-centers-compact-rows-without-duplicate-cells) printf '%s\n' "host renderer centers a compact logical screen without duplicating rows or cells" ;;
	host-vga-geometry-writer-computes-centered-render-origin) printf '%s\n' "host renderer computes the centered origin for a compact logical geometry" ;;
	source-defines-physical-vga-dimensions) printf '%s\n' "screen types define the fixed physical VGA dimensions separately from the logical preset" ;;
	source-defines-logical-to-physical-renderer) printf '%s\n' "VGA text driver defines a logical-to-physical render helper" ;;
	source-writer-centers-logical-buffer-inside-physical-vga) printf '%s\n' "writer redraw path renders the logical viewport into the fixed physical VGA buffer" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${TYPE_SOURCE}" ]] || die "missing screen type source: ${TYPE_SOURCE}"
	[[ -r "${DRIVER_SOURCE}" ]] || die "missing VGA driver source: ${DRIVER_SOURCE}"
	[[ -r "${WRITER_SOURCE}" ]] || die "missing VGA writer source: ${WRITER_SOURCE}"
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
	local test_bin="build/ut_vga_geometry_writer_${filter%_}"

	mkdir -p "$(dirname "${test_bin}")"
	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-vga-geometry-writer-centers-compact-rows-without-duplicate-cells)
		run_host_tests 'renderer_centers_compact_rows_without_duplicate_cells'
		;;
	host-vga-geometry-writer-computes-centered-render-origin)
		run_host_tests 'screen_render_origin_centers_logical_geometry_inside_physical_vga'
		;;
	source-defines-physical-vga-dimensions)
		assert_pattern '\bVGA_TEXT_PHYSICAL_DIMENSIONS\b' 'fixed physical VGA dimensions' "${TYPE_SOURCE}"
		;;
	source-defines-logical-to-physical-renderer)
		assert_pattern '\brender_logical_screen_to_physical\b|\bscreen_render_origin\b' 'logical-to-physical render helpers' "${DRIVER_SOURCE}"
		;;
	source-writer-centers-logical-buffer-inside-physical-vga)
		assert_pattern '\bVGA_TEXT_PHYSICAL_DIMENSIONS\b|\brender_logical_screen_to_physical\b|\bscreen_render_origin\b' 'writer logical-to-physical redraw path' "${WRITER_SOURCE}"
		;;
	*)
		die "usage: $0 <arch> {host-vga-geometry-writer-centers-compact-rows-without-duplicate-cells|host-vga-geometry-writer-computes-centered-render-origin|source-defines-physical-vga-dimensions|source-defines-logical-to-physical-renderer|source-writer-centers-logical-buffer-inside-physical-vga}"
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
