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
port-owner-path-fails
kernel-range-owner-path-fails
screen-types-owner-path-fails
screen-types-missing-fail
color-code-missing-repr-transparent-fails
screen-cell-missing-repr-c-fails
cursor-pos-missing-repr-c-fails
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
    port-owner-path-fails) printf '%s\n' "rejects Port ownership outside src/kernel/machine/port.rs" ;;
    kernel-range-owner-path-fails) printf '%s\n' "rejects KernelRange ownership outside src/kernel/types/range.rs" ;;
    screen-types-owner-path-fails) printf '%s\n' "rejects screen types outside src/kernel/types/screen.rs" ;;
    screen-types-missing-fail) printf '%s\n' "rejects missing future screen types" ;;
    color-code-missing-repr-transparent-fails) printf '%s\n' "rejects ColorCode without repr(transparent)" ;;
    screen-cell-missing-repr-c-fails) printf '%s\n' "rejects ScreenCell without repr(C)" ;;
    cursor-pos-missing-repr-c-fails) printf '%s\n' "rejects CursorPos without repr(C)" ;;
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
  mkdir -p "${TMPDIR}/src/kernel/machine"
  cp src/kernel/types.rs "${TMPDIR}/src/kernel/types.rs"
  cp src/kernel/types/port.rs "${TMPDIR}/src/kernel/types/port.rs"
  cp src/kernel/types/port.rs "${TMPDIR}/src/kernel/machine/port.rs"
  cp src/kernel/types/range.rs "${TMPDIR}/src/kernel/types/range.rs"
  cat >"${TMPDIR}/src/kernel/types/screen.rs" <<'EOF'
#[repr(transparent)]
pub struct ColorCode(pub u8);

#[repr(C)]
pub struct ScreenCell {
    pub ascii: u8,
    pub color: ColorCode,
}

#[repr(C)]
pub struct CursorPos {
    pub row: usize,
    pub col: usize,
}
EOF
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

check_struct_owned_only() {
  local type_name="$1"
  local owner_file="$2"
  local pattern="pub[[:space:]]+struct[[:space:]]+${type_name}\\b"
  local offenders

  if ! find_pattern "${pattern}" "${owner_file}"; then
    return 1
  fi

  if command -v rg >/dev/null 2>&1; then
    offenders="$(find "${TMPDIR}/src/kernel" -type f -name '*.rs' -print0 |
      xargs -0 rg -n "${pattern}" -S 2>/dev/null || true)"
  else
    offenders="$(find "${TMPDIR}/src/kernel" -type f -name '*.rs' -print0 |
      xargs -0 grep -EnE "${pattern}" 2>/dev/null || true)"
  fi

  offenders="$(printf '%s\n' "${offenders}" | awk -F: -v owner="${owner_file}" '$1 != owner {print}')"
  [[ -z "${offenders}" ]]
}

check_struct_repr() {
  local repr="$1"
  local struct_name="$2"
  local file="$3"

  awk -v repr="${repr}" -v name="${struct_name}" '
    $0 ~ ("#\\[repr\\(" repr "\\)\\]") { seen_repr = 1; next }
    seen_repr && $0 ~ ("pub struct " name "\\b") { found = 1; exit }
    { seen_repr = 0 }
    END { exit(found ? 0 : 1) }
  ' "${file}"
}

check_screen_types_exist() {
  find_pattern '\bstruct[[:space:]]+ColorCode\b' "$1" &&
    find_pattern '\bstruct[[:space:]]+ScreenCell\b' "$1" &&
    find_pattern '\bstruct[[:space:]]+CursorPos\b' "$1"
}

check_color_code_repr() {
  check_struct_repr 'transparent' 'ColorCode' "$1"
}

check_screen_cell_repr() {
  check_struct_repr 'C' 'ScreenCell' "$1"
}

check_cursor_pos_repr() {
  check_struct_repr 'C' 'CursorPos' "$1"
}

check_wrapper_abi() {
  find_pattern 'pub[[:space:]]+unsafe[[:space:]]+extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+kfs_' "$@"
}

check_private_impl_boundary() {
  local offenders

  if command -v rg >/dev/null 2>&1; then
    offenders="$(
      find "${TMPDIR}/src/kernel" -type f -name '*.rs' -print0 |
        xargs -0 rg -n '(string/string_impl|memory/memory_impl)\.rs' -S 2>/dev/null |
        grep -vE "^${TMPDIR}/src/kernel/(string|memory)\\.rs:" || true
    )"
  else
    offenders="$(
      find "${TMPDIR}/src/kernel" -type f -name '*.rs' -print0 |
        xargs -0 grep -En '(string/string_impl|memory/memory_impl)\.rs' 2>/dev/null |
        grep -vE "^${TMPDIR}/src/kernel/(string|memory)\\.rs:" || true
    )"
  fi

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
    port-owner-path-fails)
      expect_check_fail "Port ownership path" \
        check_struct_owned_only \
        'Port' \
        "${TMPDIR}/src/kernel/machine/port.rs"
      ;;
    kernel-range-owner-path-fails)
      cat >>"${TMPDIR}/src/kernel/kmain.rs" <<'EOF'
#[allow(dead_code)]
pub struct KernelRange {
    pub start: usize,
    pub end: usize,
}
EOF
      expect_check_fail "KernelRange ownership path" \
        check_struct_owned_only \
        'KernelRange' \
        "${TMPDIR}/src/kernel/types/range.rs"
      ;;
    screen-types-owner-path-fails)
      cat >>"${TMPDIR}/src/kernel/kmain.rs" <<'EOF'
#[repr(transparent)]
pub struct ColorCode(pub u8);

#[repr(C)]
pub struct ScreenCell {
    pub ascii: u8,
    pub color: ColorCode,
}

#[repr(C)]
pub struct CursorPos {
    pub row: usize,
    pub col: usize,
}
EOF
      expect_check_fail "ColorCode ownership path" \
        check_struct_owned_only \
        'ColorCode' \
        "${TMPDIR}/src/kernel/types/screen.rs"
      expect_check_fail "ScreenCell ownership path" \
        check_struct_owned_only \
        'ScreenCell' \
        "${TMPDIR}/src/kernel/types/screen.rs"
      expect_check_fail "CursorPos ownership path" \
        check_struct_owned_only \
        'CursorPos' \
        "${TMPDIR}/src/kernel/types/screen.rs"
      ;;
    screen-types-missing-fail)
      cat >"${TMPDIR}/src/kernel/types/screen.rs" <<'EOF'
#[repr(transparent)]
pub struct ColorCode(pub u8);
EOF
      expect_check_fail "future screen types" \
        check_screen_types_exist \
        "${TMPDIR}/src/kernel/types/screen.rs"
      ;;
    color-code-missing-repr-transparent-fails)
      sed -i '/repr(transparent)/d' "${TMPDIR}/src/kernel/types/screen.rs"
      expect_check_fail "ColorCode repr(transparent) marker" \
        check_color_code_repr \
        "${TMPDIR}/src/kernel/types/screen.rs"
      ;;
    screen-cell-missing-repr-c-fails)
      sed -i '0,/repr(C)/d' "${TMPDIR}/src/kernel/types/screen.rs"
      expect_check_fail "ScreenCell repr(C) marker" \
        check_screen_cell_repr \
        "${TMPDIR}/src/kernel/types/screen.rs"
      ;;
    cursor-pos-missing-repr-c-fails)
      perl -0pi -e 's/#\[repr\(C\)\]\npub struct CursorPos/pub struct CursorPos/' "${TMPDIR}/src/kernel/types/screen.rs"
      expect_check_fail "CursorPos repr(C) marker" \
        check_cursor_pos_repr \
        "${TMPDIR}/src/kernel/types/screen.rs"
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
      die "usage: $0 <arch> {std-in-helper-layer-fails|alias-only-primitive-layer-fails|port-missing-repr-transparent-fails|kernel-range-missing-repr-c-fails|port-owner-path-fails|kernel-range-owner-path-fails|screen-types-owner-path-fails|screen-types-missing-fail|color-code-missing-repr-transparent-fails|screen-cell-missing-repr-c-fails|cursor-pos-missing-repr-c-fails|helper-wrapper-missing-extern-c-fails|private-helper-import-fails}"
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
