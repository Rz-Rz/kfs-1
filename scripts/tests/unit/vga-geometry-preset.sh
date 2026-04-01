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
host-vga-geometry-preset-default-preset-matches-the-current-build-selection
host-vga-geometry-preset-compact-preset-changes-the-visible-geometry
host-vga-geometry-preset-history-geometry-tracks-the-selected-visible-width
host-vga-geometry-preset-unknown-preset-names-fall-back-to-the-default-geometry
source-defines-geometry-preset-selection
makefile-passes-geometry-preset-cfg
EOF
}

describe_case() {
  case "$1" in
    host-vga-geometry-preset-default-preset-matches-the-current-build-selection) printf '%s\n' "host build selection uses the compiled default geometry preset" ;;
    host-vga-geometry-preset-compact-preset-changes-the-visible-geometry) printf '%s\n' "host preset selection resolves the compact geometry" ;;
    host-vga-geometry-preset-history-geometry-tracks-the-selected-visible-width) printf '%s\n' "host history geometry keeps the selected visible width" ;;
    host-vga-geometry-preset-unknown-preset-names-fall-back-to-the-default-geometry) printf '%s\n' "host preset selection falls back to the default geometry on unknown names" ;;
    source-defines-geometry-preset-selection) printf '%s\n' "screen types define geometry presets and selection helpers" ;;
    makefile-passes-geometry-preset-cfg) printf '%s\n' "Makefile passes the geometry preset cfg into rustc builds" ;;
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
    host-vga-geometry-preset-default-preset-matches-the-current-build-selection)
      run_host_tests 'default_preset_matches_the_current_build_selection' '' ''
      run_host_tests \
        'default_preset_matches_the_current_build_selection' \
        '--cfg kfs_geometry_preset_compact40x10' \
        '--cfg kfs_expect_compact_geometry'
      ;;
    host-vga-geometry-preset-compact-preset-changes-the-visible-geometry)
      run_host_tests 'selecting_compact_preset_changes_the_visible_geometry' '' ''
      ;;
    host-vga-geometry-preset-history-geometry-tracks-the-selected-visible-width)
      run_host_tests 'history_geometry_tracks_the_selected_visible_preset_width' '' ''
      ;;
    host-vga-geometry-preset-unknown-preset-names-fall-back-to-the-default-geometry)
      run_host_tests 'unknown_preset_names_fall_back_to_the_default_geometry' '' ''
      ;;
    source-defines-geometry-preset-selection)
      assert_pattern '\bScreenGeometryPreset\b|\bselect_geometry_preset_from_name\b|\bhistory_dimensions_for_visible\b|\bDEFAULT_SCREEN_GEOMETRY_PRESET\b' 'geometry preset selection helpers' "${TYPE_SOURCE}"
      ;;
    makefile-passes-geometry-preset-cfg)
      assert_pattern 'KFS_SCREEN_GEOMETRY_PRESET|RUST_CFG_FLAGS|kfs_geometry_preset_compact40x10' 'Makefile geometry preset cfg wiring' "${MAKEFILE_SOURCE}"
      ;;
    *)
      die "usage: $0 <arch> {host-vga-geometry-preset-default-preset-matches-the-current-build-selection|host-vga-geometry-preset-compact-preset-changes-the-visible-geometry|host-vga-geometry-preset-history-geometry-tracks-the-selected-visible-width|host-vga-geometry-preset-unknown-preset-names-fall-back-to-the-default-geometry|source-defines-geometry-preset-selection|makefile-passes-geometry-preset-cfg}"
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
