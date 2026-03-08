#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
std-in-helper-layer-fails
alias-only-primitive-layer-fails
port-missing-repr-transparent-fails
kernel-range-missing-repr-c-fails
helper-wrapper-missing-extern-c-fails
private-helper-import-fails
EOF
}

describe_case() {
  case "$1" in
    std-in-helper-layer-fails) printf '%s\n' "rejects std usage in the helper/type layer" ;;
    alias-only-primitive-layer-fails) printf '%s\n' "rejects alias-only primitive wrappers in the type layer" ;;
    port-missing-repr-transparent-fails) printf '%s\n' "rejects Port without repr(transparent)" ;;
    kernel-range-missing-repr-c-fails) printf '%s\n' "rejects KernelRange without repr(C)" ;;
    helper-wrapper-missing-extern-c-fails) printf '%s\n' "rejects helper exports without extern C" ;;
    private-helper-import-fails) printf '%s\n' "rejects private helper imports outside boundary files" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

cleanup() {
  if [[ -n "${TMPDIR}" ]]; then
    rm -rf "${TMPDIR}"
  fi
}

trap cleanup EXIT

make_tmp_tree() {
  TMPDIR="$(mktemp -d)"
  mkdir -p "${TMPDIR}/src/kernel/types"
  cp src/kernel/types.rs "${TMPDIR}/src/kernel/types.rs"
  cp src/kernel/types/port.rs "${TMPDIR}/src/kernel/types/port.rs"
  cp src/kernel/types/range.rs "${TMPDIR}/src/kernel/types/range.rs"
  cp src/kernel/string.rs "${TMPDIR}/src/kernel/string.rs"
  cp src/kernel/kmain.rs "${TMPDIR}/src/kernel/kmain.rs"
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

expect_check_fail() {
  local description="$1"
  shift

  if "$@"; then
    echo "FAIL ${CASE}: ${description} unexpectedly passed"
    return 1
  fi

  echo "PASS ${CASE}: ${description} rejected"
  return 0
}

check_no_std() {
  ! find_pattern '\bstd::|extern[[:space:]]+crate[[:space:]]+std\b' "$@"
}

check_no_alias_only() {
  ! find_pattern 'type[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*(u8|u16|u32|usize|i32|isize)\b' "$@"
}

check_port_repr() {
  find_pattern '#\[repr\(transparent\)\]' "$@"
}

check_range_repr() {
  find_pattern '#\[repr\(C\)\]' "$@"
}

check_wrapper_abi() {
  find_pattern 'pub[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_' "$@"
}

check_private_impl_boundary() {
  local offenders

  offenders="$(
    find "${TMPDIR}/src/kernel" -type f -name '*.rs' -print0 |
      xargs -0 rg -n '(string/string_impl|memory/memory_impl)\.rs' -S 2>/dev/null |
      grep -vE "^${TMPDIR}/src/kernel/string\\.rs:" || true
  )"

  [[ -z "${offenders}" ]]
}

run_direct_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_tmp_tree

  case "${CASE}" in
    std-in-helper-layer-fails)
      printf 'use std::vec::Vec;\n' >>"${TMPDIR}/src/kernel/types.rs"
      expect_check_fail "std usage in helper/type layer" \
        check_no_std \
        "${TMPDIR}/src/kernel/types.rs" \
        "${TMPDIR}/src/kernel/types/port.rs" \
        "${TMPDIR}/src/kernel/types/range.rs" \
        "${TMPDIR}/src/kernel/string.rs" \
        "${TMPDIR}/src/kernel/kmain.rs"
      ;;
    alias-only-primitive-layer-fails)
      printf 'pub type Byte = u8;\n' >>"${TMPDIR}/src/kernel/types.rs"
      expect_check_fail "alias-only primitive wrapper layer" \
        check_no_alias_only \
        "${TMPDIR}/src/kernel/types.rs" \
        "${TMPDIR}/src/kernel/types/port.rs" \
        "${TMPDIR}/src/kernel/types/range.rs"
      ;;
    port-missing-repr-transparent-fails)
      sed -i '/repr(transparent)/d' "${TMPDIR}/src/kernel/types/port.rs"
      expect_check_fail "Port repr(transparent) marker" \
        check_port_repr \
        "${TMPDIR}/src/kernel/types/port.rs"
      ;;
    kernel-range-missing-repr-c-fails)
      sed -i '/repr(C)/d' "${TMPDIR}/src/kernel/types/range.rs"
      expect_check_fail "KernelRange repr(C) marker" \
        check_range_repr \
        "${TMPDIR}/src/kernel/types/range.rs"
      ;;
    helper-wrapper-missing-extern-c-fails)
      sed -i 's/extern "C" fn/fn/' "${TMPDIR}/src/kernel/string.rs"
      expect_check_fail "extern C helper wrapper" \
        check_wrapper_abi \
        "${TMPDIR}/src/kernel/string.rs"
      ;;
    private-helper-import-fails)
      printf '\n#[path = "string/string_impl.rs"]\nmod leaked_impl;\n' >>"${TMPDIR}/src/kernel/kmain.rs"
      expect_check_fail "private helper import outside boundary file" \
        check_private_impl_boundary
      ;;
    *)
      die "usage: $0 <arch> {std-in-helper-layer-fails|alias-only-primitive-layer-fails|port-missing-repr-transparent-fails|kernel-range-missing-repr-c-fails|helper-wrapper-missing-extern-c-fails|private-helper-import-fails}"
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

  run_direct_case
}

main "$@"
