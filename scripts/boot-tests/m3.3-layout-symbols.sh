#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
LAYOUT_SYMBOLS_SRC="src/rust/layout_symbols.rs"

list_cases() {
  cat <<'EOF'
release-kernel-exports-kernel-start
release-kernel-exports-kernel-end
release-kernel-exports-bss-start
release-kernel-exports-bss-end
release-kernel-links-layout-symbols-marker
release-symbol-ordering
test-kernel-exports-kernel-start
test-kernel-exports-kernel-end
test-kernel-exports-bss-start
test-kernel-exports-bss-end
test-kernel-links-layout-symbols-marker
test-symbol-ordering
rust-declares-layout-symbols
rust-references-kernel-start
rust-references-kernel-end
rust-references-bss-start
rust-references-bss-end
EOF
}

describe_case() {
  case "$1" in
    release-kernel-exports-kernel-start) printf '%s\n' "release kernel exports kernel_start" ;;
    release-kernel-exports-kernel-end) printf '%s\n' "release kernel exports kernel_end" ;;
    release-kernel-exports-bss-start) printf '%s\n' "release kernel exports bss_start" ;;
    release-kernel-exports-bss-end) printf '%s\n' "release kernel exports bss_end" ;;
    release-kernel-links-layout-symbols-marker) printf '%s\n' "release kernel links kfs_layout_symbols_marker" ;;
    release-symbol-ordering) printf '%s\n' "release layout symbols are monotonic" ;;
    test-kernel-exports-kernel-start) printf '%s\n' "test kernel exports kernel_start" ;;
    test-kernel-exports-kernel-end) printf '%s\n' "test kernel exports kernel_end" ;;
    test-kernel-exports-bss-start) printf '%s\n' "test kernel exports bss_start" ;;
    test-kernel-exports-bss-end) printf '%s\n' "test kernel exports bss_end" ;;
    test-kernel-links-layout-symbols-marker) printf '%s\n' "test kernel links kfs_layout_symbols_marker" ;;
    test-symbol-ordering) printf '%s\n' "test layout symbols are monotonic" ;;
    rust-declares-layout-symbols) printf '%s\n' "Rust declares extern \"C\" layout symbols" ;;
    rust-references-kernel-start) printf '%s\n' "Rust references kernel_start" ;;
    rust-references-kernel-end) printf '%s\n' "Rust references kernel_end" ;;
    rust-references-bss-start) printf '%s\n' "Rust references bss_start" ;;
    rust-references-bss-end) printf '%s\n' "Rust references bss_end" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

find_src_pattern() {
  local pattern="$1"

  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S src >/dev/null
  else
    grep -REn "${pattern}" src >/dev/null
  fi
}

find_layout_symbols_src_pattern() {
  local pattern="$1"
  [[ -r "${LAYOUT_SYMBOLS_SRC}" ]] || die "missing Rust layout symbol consumer: ${LAYOUT_SYMBOLS_SRC}"

  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S "${LAYOUT_SYMBOLS_SRC}" >/dev/null
  else
    grep -En "${pattern}" "${LAYOUT_SYMBOLS_SRC}" >/dev/null
  fi
}

symbol_address_hex() {
  local kernel="$1"
  local symbol="$2"
  local address

  address="$(nm -n "${kernel}" | awk -v symbol="${symbol}" '$3 == symbol { print $1; exit }')"
  [[ -n "${address}" ]] || die "missing layout symbol ${symbol} in ${kernel}"
  printf '%s\n' "${address}"
}

assert_symbol_ordering() {
  local kernel="$1"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel}"

  local kernel_start_hex kernel_end_hex bss_start_hex bss_end_hex
  local kernel_start_dec kernel_end_dec bss_start_dec bss_end_dec
  kernel_start_hex="$(symbol_address_hex "${kernel}" 'kernel_start')"
  kernel_end_hex="$(symbol_address_hex "${kernel}" 'kernel_end')"
  bss_start_hex="$(symbol_address_hex "${kernel}" 'bss_start')"
  bss_end_hex="$(symbol_address_hex "${kernel}" 'bss_end')"

  kernel_start_dec=$((16#${kernel_start_hex}))
  kernel_end_dec=$((16#${kernel_end_hex}))
  bss_start_dec=$((16#${bss_start_hex}))
  bss_end_dec=$((16#${bss_end_hex}))

  if (( kernel_start_dec > bss_start_dec )); then
    echo "FAIL ${kernel}: kernel_start > bss_start (${kernel_start_hex} > ${bss_start_hex})"
    return 1
  fi

  if (( bss_start_dec > bss_end_dec )); then
    echo "FAIL ${kernel}: bss_start > bss_end (${bss_start_hex} > ${bss_end_hex})"
    return 1
  fi

  if (( bss_end_dec > kernel_end_dec )); then
    echo "FAIL ${kernel}: bss_end > kernel_end (${bss_end_hex} > ${kernel_end_hex})"
    return 1
  fi

  echo "PASS ${kernel}: kernel_start <= bss_start <= bss_end <= kernel_end"
  return 0
}

assert_kernel_exports_symbol() {
  local kernel="$1"
  local symbol="$2"
  [[ -r "${kernel}" ]] || die "missing artifact: ${kernel}"

  if ! nm -n "${kernel}" | grep -qw "${symbol}"; then
    echo "FAIL ${kernel}: missing layout symbol ${symbol}"
    return 1
  fi

  echo "PASS ${kernel}: ${symbol}"
  return 0
}

assert_rust_declares_layout_symbols() {
  if ! find_layout_symbols_src_pattern 'unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]*\{'; then
    echo "FAIL src: no extern \"C\" layout declaration found"
    return 1
  fi

  local symbol
  for symbol in kernel_start kernel_end bss_start bss_end; do
    if ! find_layout_symbols_src_pattern "static[[:space:]]+${symbol}:[[:space:]]+u8;"; then
      echo "FAIL ${LAYOUT_SYMBOLS_SRC}: missing declaration for ${symbol}"
      return 1
    fi
  done

  echo "PASS ${LAYOUT_SYMBOLS_SRC}: extern \"C\" layout declaration"
  return 0
}

assert_rust_references_symbol() {
  local symbol="$1"
  if ! find_layout_symbols_src_pattern "addr_of!\\([[:space:]]*${symbol}[[:space:]]*\\)"; then
    echo "FAIL ${LAYOUT_SYMBOLS_SRC}: missing Rust reference to ${symbol}"
    return 1
  fi

  echo "PASS ${LAYOUT_SYMBOLS_SRC}: ${symbol}"
  return 0
}

run_direct_case() {
  case "${CASE}" in
    release-kernel-exports-kernel-start)
      assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'kernel_start'
      ;;
    release-kernel-exports-kernel-end)
      assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'kernel_end'
      ;;
    release-kernel-exports-bss-start)
      assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'bss_start'
      ;;
    release-kernel-exports-bss-end)
      assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'bss_end'
      ;;
    release-kernel-links-layout-symbols-marker)
      assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'kfs_layout_symbols_marker'
      ;;
    release-symbol-ordering)
      assert_symbol_ordering "build/kernel-${ARCH}.bin"
      ;;
    test-kernel-exports-kernel-start)
      assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'kernel_start'
      ;;
    test-kernel-exports-kernel-end)
      assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'kernel_end'
      ;;
    test-kernel-exports-bss-start)
      assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'bss_start'
      ;;
    test-kernel-exports-bss-end)
      assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'bss_end'
      ;;
    test-kernel-links-layout-symbols-marker)
      assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'kfs_layout_symbols_marker'
      ;;
    test-symbol-ordering)
      assert_symbol_ordering "build/kernel-${ARCH}-test.bin"
      ;;
    rust-declares-layout-symbols)
      assert_rust_declares_layout_symbols
      ;;
    rust-references-kernel-start)
      assert_rust_references_symbol 'kernel_start'
      ;;
    rust-references-kernel-end)
      assert_rust_references_symbol 'kernel_end'
      ;;
    rust-references-bss-start)
      assert_rust_references_symbol 'bss_start'
      ;;
    rust-references-bss-end)
      assert_rust_references_symbol 'bss_end'
      ;;
    *)
      die "usage: $0 <arch> {release-kernel-exports-kernel-start|release-kernel-exports-kernel-end|release-kernel-exports-bss-start|release-kernel-exports-bss-end|release-kernel-links-layout-symbols-marker|release-symbol-ordering|test-kernel-exports-kernel-start|test-kernel-exports-kernel-end|test-kernel-exports-bss-start|test-kernel-exports-bss-end|test-kernel-links-layout-symbols-marker|test-symbol-ordering|rust-declares-layout-symbols|rust-references-kernel-start|rust-references-kernel-end|rust-references-bss-start|rust-references-bss-end}"
      ;;
  esac
}

run_host_case() {
  case "${CASE}" in
    release-kernel-exports-kernel-start|release-kernel-exports-kernel-end|release-kernel-exports-bss-start|release-kernel-exports-bss-end|release-kernel-links-layout-symbols-marker|release-symbol-ordering)
      bash scripts/container.sh run -- \
        bash -lc "make -B all arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/m3.3-layout-symbols.sh '${ARCH}' '${CASE}'"
      ;;
    test-kernel-exports-kernel-start|test-kernel-exports-kernel-end|test-kernel-exports-bss-start|test-kernel-exports-bss-end|test-kernel-links-layout-symbols-marker|test-symbol-ordering)
      bash scripts/container.sh run -- \
        bash -lc "make -B iso-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL:-0}' >/dev/null && KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/m3.3-layout-symbols.sh '${ARCH}' '${CASE}'"
      ;;
    rust-declares-layout-symbols|rust-references-kernel-start|rust-references-kernel-end|rust-references-bss-start|rust-references-bss-end)
      run_direct_case
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

  if [[ -n "${CASE}" ]] && describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  if [[ -n "${CASE}" ]]; then
    run_direct_case
    return 0
  fi

  local failures=0

  [[ -r "build/kernel-${ARCH}-test.bin" ]] || die "missing test kernel: build/kernel-${ARCH}-test.bin (build it with make iso-test arch=${ARCH})"
  assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'kernel_start' || failures=$((failures + 1))
  assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'kernel_end' || failures=$((failures + 1))
  assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'bss_start' || failures=$((failures + 1))
  assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'bss_end' || failures=$((failures + 1))
  assert_kernel_exports_symbol "build/kernel-${ARCH}-test.bin" 'kfs_layout_symbols_marker' || failures=$((failures + 1))
  assert_symbol_ordering "build/kernel-${ARCH}-test.bin" || failures=$((failures + 1))
  assert_rust_declares_layout_symbols || failures=$((failures + 1))
  assert_rust_references_symbol 'kernel_start' || failures=$((failures + 1))
  assert_rust_references_symbol 'kernel_end' || failures=$((failures + 1))
  assert_rust_references_symbol 'bss_start' || failures=$((failures + 1))
  assert_rust_references_symbol 'bss_end' || failures=$((failures + 1))

  if [[ "${KFS_M3_3_INCLUDE_RELEASE:-0}" == "1" ]]; then
    [[ -r "build/kernel-${ARCH}.bin" ]] || die "missing release kernel: build/kernel-${ARCH}.bin (build it with make all arch=${ARCH})"
    assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'kernel_start' || failures=$((failures + 1))
    assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'kernel_end' || failures=$((failures + 1))
    assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'bss_start' || failures=$((failures + 1))
    assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'bss_end' || failures=$((failures + 1))
    assert_kernel_exports_symbol "build/kernel-${ARCH}.bin" 'kfs_layout_symbols_marker' || failures=$((failures + 1))
    assert_symbol_ordering "build/kernel-${ARCH}.bin" || failures=$((failures + 1))
  fi

  if [[ "${failures}" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
