#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_types.rs"
TYPES_SOURCE="src/kernel/types.rs"
PORT_SOURCE="src/kernel/types/port.rs"
RANGE_SOURCE="src/kernel/types/range.rs"
KMAIN_SOURCE="src/kernel/kmain.rs"
KMAIN_IMPL="src/kernel/kmain/logic_impl.rs"
STRING_SOURCE="src/kernel/string.rs"

list_cases() {
  cat <<'EOF'
port-host-unit-tests-pass
kernel-range-host-unit-tests-pass
helper-boundary-files-exist
helper-abi-uses-primitive-core-types
kernel-helper-code-avoids-std
no-alias-only-primitive-layer
port-uses-repr-transparent
kernel-range-uses-repr-c
helper-wrappers-use-extern-c-and-no-mangle
helper-private-impl-not-imported-directly
serial-path-uses-port-type
layout-path-uses-kernel-range-type
EOF
}

describe_case() {
  case "$1" in
    port-host-unit-tests-pass) printf '%s\n' "host Port unit tests pass" ;;
    kernel-range-host-unit-tests-pass) printf '%s\n' "host KernelRange unit tests pass" ;;
    helper-boundary-files-exist) printf '%s\n' "helper boundary and type facade files exist" ;;
    helper-abi-uses-primitive-core-types) printf '%s\n' "helper ABI uses primitive/core-compatible types only" ;;
    kernel-helper-code-avoids-std) printf '%s\n' "helper and type code avoids std" ;;
    no-alias-only-primitive-layer) printf '%s\n' "type layer avoids alias-only primitive wrappers" ;;
    port-uses-repr-transparent) printf '%s\n' "Port uses repr(transparent)" ;;
    kernel-range-uses-repr-c) printf '%s\n' "KernelRange uses repr(C)" ;;
    helper-wrappers-use-extern-c-and-no-mangle) printf '%s\n' "helper wrappers keep extern C and no_mangle" ;;
    helper-private-impl-not-imported-directly) printf '%s\n' "private helper impl files are not imported directly outside boundary files" ;;
    serial-path-uses-port-type) printf '%s\n' "serial path uses Port instead of raw u16 ports" ;;
    layout-path-uses-kernel-range-type) printf '%s\n' "layout path uses KernelRange instead of naked pairs" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

ensure_sources_exist() {
  local path

  for path in \
    "${TEST_SOURCE}" \
    "${TYPES_SOURCE}" \
    "${PORT_SOURCE}" \
    "${RANGE_SOURCE}" \
    "${KMAIN_SOURCE}" \
    "${KMAIN_IMPL}" \
    "${STRING_SOURCE}"; do
    [[ -r "${path}" ]] || die "missing required source: ${path}"
  done
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

assert_no_pattern() {
  local pattern="$1"
  local label="$2"
  shift 2

  if find_pattern "${pattern}" "$@"; then
    echo "FAIL src: found ${label}"
    if command -v rg >/dev/null 2>&1; then
      rg -n "${pattern}" -S "$@" || true
    else
      grep -En "${pattern}" "$@" || true
    fi
    return 1
  fi

  echo "PASS src: ${label}"
  return 0
}

run_host_tests() {
  local filter="$1"
  local test_bin="build/ut_types_${filter%_}"

  bash scripts/container.sh run -- \
    bash -lc "mkdir -p build && rustc --test -o '${test_bin}' '${TEST_SOURCE}' >/dev/null && '${test_bin}' '${filter}'"
}

assert_files_exist() {
  ensure_sources_exist
  echo "PASS files: helper boundary and type facade files exist"
}

assert_helper_abi_uses_primitive_types() {
  assert_pattern '#\[no_mangle\]' 'no_mangle helper export' "${STRING_SOURCE}"
  assert_pattern 'pub[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_' 'extern C helper export' "${STRING_SOURCE}"
  assert_no_pattern 'fn[[:space:]]+kfs_[A-Za-z0-9_]+\([^)]*(String|Vec|Option|Result|&|\[[^]]*\])' 'forbidden ABI types in helper exports' "${STRING_SOURCE}"
}

assert_private_impl_boundary() {
  local offenders

  offenders="$(
    find src/kernel -type f -name '*.rs' -print0 |
      xargs -0 rg -n '(string/string_impl|memory/memory_impl)\.rs' -S 2>/dev/null |
      grep -vE '^src/kernel/(string|memory)\.rs:' || true
  )"

  if [[ -n "${offenders}" ]]; then
    echo "FAIL src: found private helper import outside public boundary file"
    printf '%s\n' "${offenders}"
    return 1
  fi

  echo "PASS src: private helper imports stay in boundary files"
}

run_direct_case() {
  ensure_sources_exist

  case "${CASE}" in
    port-host-unit-tests-pass)
      run_host_tests 'port_'
      ;;
    kernel-range-host-unit-tests-pass)
      run_host_tests 'kernel_range_'
      ;;
    helper-boundary-files-exist)
      assert_files_exist
      ;;
    helper-abi-uses-primitive-core-types)
      assert_helper_abi_uses_primitive_types
      ;;
    kernel-helper-code-avoids-std)
      assert_no_pattern '\bstd::|extern[[:space:]]+crate[[:space:]]+std\b' 'std usage in helper/type layer' \
        "${TYPES_SOURCE}" "${PORT_SOURCE}" "${RANGE_SOURCE}" "${STRING_SOURCE}" "${KMAIN_SOURCE}" "${KMAIN_IMPL}"
      ;;
    no-alias-only-primitive-layer)
      assert_no_pattern 'type[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*(u8|u16|u32|usize|i32|isize)\b' 'alias-only primitive type wrapper' \
        "${TYPES_SOURCE}" "${PORT_SOURCE}" "${RANGE_SOURCE}"
      ;;
    port-uses-repr-transparent)
      assert_pattern '#\[repr\(transparent\)\]' 'Port repr(transparent)' "${PORT_SOURCE}"
      ;;
    kernel-range-uses-repr-c)
      assert_pattern '#\[repr\(C\)\]' 'KernelRange repr(C)' "${RANGE_SOURCE}"
      ;;
    helper-wrappers-use-extern-c-and-no-mangle)
      assert_pattern '#\[no_mangle\]' 'no_mangle helper wrapper' "${STRING_SOURCE}"
      assert_pattern 'pub[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_' 'extern C helper wrapper' "${STRING_SOURCE}"
      ;;
    helper-private-impl-not-imported-directly)
      assert_private_impl_boundary
      ;;
    serial-path-uses-port-type)
      assert_pattern 'const[[:space:]]+COM1_DATA:[[:space:]]+Port[[:space:]]*=' 'Port-based serial constant' "${KMAIN_SOURCE}"
      assert_pattern 'fn[[:space:]]+outb\(port:[[:space:]]+Port,[[:space:]]+value:[[:space:]]+u8\)' 'Port-based outb signature' "${KMAIN_SOURCE}"
      assert_pattern 'fn[[:space:]]+inb\(port:[[:space:]]+Port\)[[:space:]]*->[[:space:]]+u8' 'Port-based inb signature' "${KMAIN_SOURCE}"
      ;;
    layout-path-uses-kernel-range-type)
      assert_pattern 'KernelRange::new\(' 'KernelRange construction in kmain' "${KMAIN_SOURCE}"
      assert_pattern 'use[[:space:]]+super::kernel_types::KernelRange;' 'KernelRange import in layout helper module' "${KMAIN_IMPL}"
      assert_pattern 'layout_order_is_sane\(kernel,[[:space:]]*bss,[[:space:]]*layout_override\)' 'KernelRange-based layout helper call from kmain' "${KMAIN_SOURCE}"
      ;;
    *)
      die "usage: $0 <arch> {port-host-unit-tests-pass|kernel-range-host-unit-tests-pass|helper-boundary-files-exist|helper-abi-uses-primitive-core-types|kernel-helper-code-avoids-std|no-alias-only-primitive-layer|port-uses-repr-transparent|kernel-range-uses-repr-c|helper-wrappers-use-extern-c-and-no-mangle|helper-private-impl-not-imported-directly|serial-path-uses-port-type|layout-path-uses-kernel-range-type}"
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
