#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_color.rs"
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
host-vga-color-attribute-packs-foreground-and-background
host-vga-color-attribute-masks-values-to-low-nibble
host-vga-color-default-attribute-is-green-on-black
host-vga-color-enum-values-match-vga-codes
host-vga-color-enum-from-index-wraps-in-palette-range
host-vga-color-api-updates-writer-attribute
source-defines-vga-attribute-model
source-defines-vga-color-palette
source-defines-vga-color-api
EOF
}

describe_case() {
	case "$1" in
	host-vga-color-attribute-packs-foreground-and-background) printf '%s\n' "host VGA color model packs foreground and background nibbles" ;;
	host-vga-color-attribute-masks-values-to-low-nibble) printf '%s\n' "host VGA color model masks inputs to the low VGA nibble" ;;
	host-vga-color-default-attribute-is-green-on-black) printf '%s\n' "host VGA default attribute stays green on black" ;;
	host-vga-color-enum-values-match-vga-codes) printf '%s\n' "host VGA color enum values match expected VGA palette codes" ;;
	host-vga-color-enum-from-index-wraps-in-palette-range) printf '%s\n' "host VGA color enum wraps index-based selection across the palette range" ;;
	host-vga-color-api-updates-writer-attribute) printf '%s\n' "host VGA color API updates the active writer attribute" ;;
	source-defines-vga-attribute-model) printf '%s\n' "source defines the VGA attribute packing model" ;;
	source-defines-vga-color-palette) printf '%s\n' "source defines the VGA color palette enum and index mapping" ;;
	source-defines-vga-color-api) printf '%s\n' "source defines a configurable VGA color API in the driver" ;;
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
	local test_bin="build/ut_vga_color_${filter%_}"

	run_host_rust_test "${TEST_SOURCE}" "${test_bin}" "${filter}"
}

run_direct_case() {
	ensure_sources_exist

	case "${CASE}" in
	host-vga-color-attribute-packs-foreground-and-background)
		run_host_tests 'attribute_packs_foreground_and_background'
		;;
	host-vga-color-attribute-masks-values-to-low-nibble)
		run_host_tests 'attribute_masks_values_to_low_nibble'
		;;
	host-vga-color-default-attribute-is-green-on-black)
		run_host_tests 'default_attribute_is_green_on_black'
		;;
	host-vga-color-enum-values-match-vga-codes)
		run_host_tests 'enum_color_values_match_vga_codes'
		;;
	host-vga-color-enum-from-index-wraps-in-palette-range)
		run_host_tests 'enum_from_index_wraps_in_palette_range'
		;;
	host-vga-color-api-updates-writer-attribute)
		run_host_tests 'color_api_updates_the_active_writer_attribute'
		;;
	source-defines-vga-attribute-model)
		assert_pattern '\bvga_attribute\b|\bvga_color_nibble\b' 'VGA attribute packing helpers' "${TYPE_SOURCE}"
		;;
	source-defines-vga-color-palette)
		assert_pattern '\benum[[:space:]]+VgaColor\b|\bVgaColor::from_index\b|\bVgaColor::ALL\b' 'VGA color palette enum and index mapping' "${TYPE_SOURCE}"
		;;
	source-defines-vga-color-api)
		assert_pattern '\bvga_text_set_color\b|\bvga_text_get_color\b' 'driver-level VGA color API' "${DRIVER_SOURCE}"
		assert_pattern '\bset_color\b|\bcolor\b' 'writer-level VGA color state accessors' "${WRITER_SOURCE}"
		;;
	*)
		die "usage: $0 <arch> {host-vga-color-attribute-packs-foreground-and-background|host-vga-color-attribute-masks-values-to-low-nibble|host-vga-color-default-attribute-is-green-on-black|host-vga-color-enum-values-match-vga-codes|host-vga-color-enum-from-index-wraps-in-palette-range|host-vga-color-api-updates-writer-attribute|source-defines-vga-attribute-model|source-defines-vga-color-palette|source-defines-vga-color-api}"
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
