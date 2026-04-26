#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_geometry_preset.rs"
TYPE_SOURCE="src/kernel/types/screen.rs"
MAKEFILE_SOURCE="Makefile"
source "$(dirname "${BASH_SOURCE[0]}")/host-rust-lib.sh"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
host-vga-geometry-is-fixed-to-standard-vga
host-vga-history-geometry-tracks-the-fixed-visible-width
source-removes-geometry-preset-selection
makefile-removes-geometry-preset-cfg
EOF
}

describe_case() {
	case "$1" in
	host-vga-geometry-is-fixed-to-standard-vga) printf '%s\n' "host VGA geometry stays fixed at the standard 80x25 dimensions" ;;
	host-vga-history-geometry-tracks-the-fixed-visible-width) printf '%s\n' "host history geometry keeps the fixed visible width" ;;
	source-removes-geometry-preset-selection) printf '%s\n' "screen types no longer define alternate geometry preset selectors" ;;
	makefile-removes-geometry-preset-cfg) printf '%s\n' "Makefile no longer exposes geometry preset cfg wiring" ;;
	*) return 1 ;;
	esac
}

ensure_sources_exist() {
	[[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
	[[ -r "${TYPE_SOURCE}" ]] || die "missing screen type source: ${TYPE_SOURCE}"
	[[ -r "${MAKEFILE_SOURCE}" ]] || die "missing Makefile"
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

run_host_tests() {
	local filter="$1"
	local lib_flags="$2"
	local test_flags="$3"
	local test_bin="build/ut_vga_geometry_preset_${filter%_}"

	mkdir -p "$(dirname "${test_bin}")"
	KFS_HOST_LIB_RUSTC_FLAGS="${lib_flags}" KFS_HOST_TEST_RUSTC_FLAGS="${test_flags}" \
		run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-vga-geometry-is-fixed-to-standard-vga)
		run_host_tests 'vga_text_dimensions_are_fixed_to_standard_vga' '' ''
		;;
	host-vga-history-geometry-tracks-the-fixed-visible-width)
		run_host_tests \
			'history_geometry_tracks_the_fixed_visible_width' \
			'' \
			''
		;;
	source-removes-geometry-preset-selection)
		assert_no_pattern '\bScreenGeometryPreset\b|\bselect_geometry_preset_from_name\b|\bhistory_dimensions_for_visible\b|\bDEFAULT_SCREEN_GEOMETRY_PRESET\b|\bkfs_geometry_preset_compact40x10\b' 'geometry preset selection helpers' "${TYPE_SOURCE}"
		;;
	makefile-removes-geometry-preset-cfg)
		assert_no_pattern 'KFS_SCREEN_GEOMETRY_PRESET|kfs_geometry_preset_compact40x10|run-ui-compact' 'Makefile geometry preset cfg wiring' "${MAKEFILE_SOURCE}"
		assert_pattern 'run-ui' 'Makefile standard VGA UI target' "${MAKEFILE_SOURCE}"
		;;
	*)
		die "usage: $0 <arch> {host-vga-geometry-is-fixed-to-standard-vga|host-vga-history-geometry-tracks-the-fixed-visible-width|source-removes-geometry-preset-selection|makefile-removes-geometry-preset-cfg}"
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
