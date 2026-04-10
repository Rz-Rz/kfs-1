#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TYPE_SOURCE="src/kernel/types/screen.rs"
DRIVER_SOURCE="src/kernel/drivers/vga_text/mod.rs"
WRITER_SOURCE="src/kernel/drivers/vga_text/writer.rs"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
source-removes-physical-vga-dimensions
source-removes-logical-to-physical-renderer
source-writer-redraws-directly-into-the-standard-vga-buffer
EOF
}

describe_case() {
	case "$1" in
	source-removes-physical-vga-dimensions) printf '%s\n' "screen types no longer split logical and physical VGA dimensions" ;;
	source-removes-logical-to-physical-renderer) printf '%s\n' "VGA text driver no longer defines logical-to-physical centering helpers" ;;
	source-writer-redraws-directly-into-the-standard-vga-buffer) printf '%s\n' "writer redraw path blits directly into one standard VGA shadow buffer" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
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

assert_no_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2

	if find_pattern "${pattern}" "$@"; then
		echo "FAIL src: found ${label}"
		return 1
	fi

	echo "PASS src: ${label}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	source-removes-physical-vga-dimensions)
		assert_no_pattern '\bVGA_TEXT_PHYSICAL_DIMENSIONS\b|\bScreenPosition\b' 'physical/logical VGA split helpers' "${TYPE_SOURCE}"
		;;
	source-removes-logical-to-physical-renderer)
		assert_no_pattern '\brender_logical_screen_to_physical\b|\bscreen_render_origin\b' 'logical-to-physical render helpers' "${DRIVER_SOURCE}"
		;;
	source-writer-redraws-directly-into-the-standard-vga-buffer)
		assert_pattern '\bstatic mut VGA_SHADOW\b' 'single VGA shadow buffer' "${WRITER_SOURCE}"
		assert_pattern '\bvga_text_blit_viewport\b' 'direct viewport blit' "${WRITER_SOURCE}"
		assert_pattern '\bvga_set_hardware_cursor\(cursor_row, terminal\.cursor\.col\)' 'direct hardware cursor positioning' "${WRITER_SOURCE}"
		assert_no_pattern '\brender_logical_screen_to_physical\b|\bscreen_render_origin\b|\bVGA_TEXT_PHYSICAL_DIMENSIONS\b' 'legacy centered redraw path' "${WRITER_SOURCE}"
		;;
	*)
		die "usage: $0 <arch> {source-removes-physical-vga-dimensions|source-removes-logical-to-physical-renderer|source-writer-redraws-directly-into-the-standard-vga-buffer}"
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
