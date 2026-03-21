#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_kmain_logic.rs"
KMAIN_SOURCE="src/kernel/kmain.rs"
KMAIN_IMPL="src/kernel/kmain/logic_impl.rs"

list_cases() {
  cat <<'EOF'
host-layout-order-unit-tests-pass
host-vga-cell-unit-tests-pass
rust-defines-layout-order-check
rust-defines-vga-text-cell
rust-kmain-uses-layout-order-check
rust-kmain-uses-vga-writer
EOF
}

describe_case() {
  case "$1" in
    host-layout-order-unit-tests-pass) printf '%s\n' "host layout-order unit tests pass" ;;
    host-vga-cell-unit-tests-pass) printf '%s\n' "host VGA text cell unit tests pass" ;;
    rust-defines-layout-order-check) printf '%s\n' "Rust defines the pure layout-order helper" ;;
    rust-defines-vga-text-cell) printf '%s\n' "Rust defines the VGA text cell helper" ;;
    rust-kmain-uses-layout-order-check) printf '%s\n' "kmain uses the shared layout-order helper" ;;
    rust-kmain-uses-vga-writer) printf '%s\n' "kmain uses the VGA writer interface" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

ensure_sources_exist() {
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
  [[ -r "${KMAIN_SOURCE}" ]] || die "missing kernel source: ${KMAIN_SOURCE}"
  [[ -r "${KMAIN_IMPL}" ]] || die "missing kmain logic implementation: ${KMAIN_IMPL}"
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

run_host_tests() {
  local filter="$1"
  local test_bin="build/ut_kmain_logic_${filter%_}"

  bash scripts/container.sh run -- \
    bash -lc "mkdir -p build && rustc --test -o '${test_bin}' '${TEST_SOURCE}' >/dev/null && '${test_bin}' '${filter}'"
}

run_direct_case() {
  ensure_sources_exist

  case "${CASE}" in
    host-layout-order-unit-tests-pass)
      run_host_tests 'layout_order_'
      ;;
    host-vga-cell-unit-tests-pass)
      run_host_tests 'vga_text_cell_'
      ;;
    rust-defines-layout-order-check)
      assert_pattern '\bfn[[:space:]]+layout_order_is_sane\b' 'layout_order_is_sane definition' "${KMAIN_IMPL}"
      ;;
    rust-defines-vga-text-cell)
      assert_pattern '\bfn[[:space:]]+vga_text_cell\b' 'vga_text_cell definition' "${KMAIN_IMPL}"
      ;;
    rust-kmain-uses-layout-order-check)
      assert_pattern '\blayout_order_is_sane\(' 'kmain call to layout_order_is_sane' "${KMAIN_SOURCE}"
      ;;
    rust-kmain-uses-vga-writer)
      assert_pattern '\bvga_init\(' 'kmain call to vga_init' "${KMAIN_SOURCE}"
      assert_pattern '\bvga_puts\(' 'kmain call to vga_puts' "${KMAIN_SOURCE}"
      ;;
    *)
      die "usage: $0 <arch> {host-layout-order-unit-tests-pass|host-vga-cell-unit-tests-pass|rust-defines-layout-order-check|rust-defines-vga-text-cell|rust-kmain-uses-layout-order-check|rust-kmain-uses-vga-writer}"
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
