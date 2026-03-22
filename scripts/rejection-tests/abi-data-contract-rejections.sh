#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
abi-export-reference-types-fails
abi-export-slice-or-str-fails
abi-export-tuple-fails
abi-export-unrepr-user-type-fails
abi-export-trait-object-fails
abi-export-generic-fn-fails
abi-export-option-result-fails
abi-export-allocator-type-fails
EOF
}

describe_case() {
  case "$1" in
    abi-export-reference-types-fails) printf '%s\n' "reject exported ABI signatures with references" ;;
    abi-export-slice-or-str-fails) printf '%s\n' "reject exported ABI signatures with slices or str" ;;
    abi-export-tuple-fails) printf '%s\n' "reject exported ABI signatures with tuples" ;;
    abi-export-unrepr-user-type-fails) printf '%s\n' "reject exported ABI signatures with unrepr user types" ;;
    abi-export-trait-object-fails) printf '%s\n' "reject exported ABI signatures with trait objects" ;;
    abi-export-generic-fn-fails) printf '%s\n' "reject generic exported ABI functions" ;;
    abi-export-option-result-fails) printf '%s\n' "reject Option/Result in exported ABI signatures" ;;
    abi-export-allocator-type-fails) printf '%s\n' "reject allocator-backed exported ABI signatures" ;;
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

make_tree() {
  TMPDIR="$(mktemp -d)"
  mkdir -p \
    "${TMPDIR}/src/kernel/core" \
    "${TMPDIR}/src/kernel/klib/string" \
    "${TMPDIR}/src/kernel/klib/memory" \
    "${TMPDIR}/src/kernel/types"

  cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
#[no_mangle]
pub extern "C" fn kmain() -> ! {
    loop {}
}
EOF

  cat >"${TMPDIR}/src/kernel/klib/string/mod.rs" <<'EOF'
#[no_mangle]
pub unsafe extern "C" fn kfs_strlen(ptr: *const u8) -> usize {
    ptr as usize as usize
}

#[no_mangle]
pub unsafe extern "C" fn kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32 {
    if lhs == rhs { 0 } else { 1 }
}
EOF

  cat >"${TMPDIR}/src/kernel/klib/memory/mod.rs" <<'EOF'
#[no_mangle]
pub unsafe extern "C" fn kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    let _ = (src, len);
    dst
}

#[no_mangle]
pub unsafe extern "C" fn kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    let _ = (value, len);
    dst
}
EOF

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
}

expect_failure() {
  local description="$1"
  shift

  if "$@"; then
    echo "FAIL ${CASE}: ${description} unexpectedly passed"
    return 1
  fi

  echo "PASS ${CASE}: ${description} rejected"
}

check_no_references() {
  ! rg -n '^\s*(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn[^(]*\([^)]*&[^)]*\)\s*(?:->\s*[^\\{;]+)?\s*\{' \
    "${TMPDIR}/src/kernel" >/dev/null
}

check_no_slices_or_str() {
  ! rg -n '^\s*(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn[^(]*\([^)]*str[^)]*\)\s*(?:->\s*[^\\{;]+)?\s*\{' \
    "${TMPDIR}/src/kernel" >/dev/null \
    && ! rg -n '^\s*(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn[^(]*\([^)]*\[[^\];]+\][^)]*\)\s*(?:->\s*[^\\{;]+)?\s*\{' \
    "${TMPDIR}/src/kernel" >/dev/null
}

check_no_tuples() {
  ! rg -n '^\s*(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn[^(]*\([^)]*\([^)]*,\s*[^)]*\)[^)]*\)\s*(?:->\s*[^\\{;]+)?\s*\{' \
    "${TMPDIR}/src/kernel" >/dev/null
}

check_no_unrepr_user_type() {
  ! rg -n 'bad_unrepr\([^)]*\s*:\s*RawPair' "${TMPDIR}/src/kernel" >/dev/null
}

check_no_trait_objects() {
  ! rg -n '^\s*(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn[^(]*\([^)]*dyn\s+[^)]*\)\s*(?:->\s*[^\\{;]+)?\s*\{' \
    "${TMPDIR}/src/kernel" >/dev/null
}

check_no_generic_exports() {
  ! rg -n '^\s*(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn[^(]*<[^>]+>[^\\{]*\{' "${TMPDIR}/src/kernel" >/dev/null
}

check_no_option_result() {
  ! rg -n 'extern[[:space:]]+"C"[[:space:]]+fn[^(]*\([^)]*([A-Za-z0-9_]+::)*(Option|Result)\s*<[^)]*' \
    "${TMPDIR}/src/kernel" >/dev/null
}

check_no_allocator_types() {
  ! rg -n '^\s*(?:pub\s+)?(?:unsafe\s+)?extern\s+"C"\s+fn[^(]*\([^)]*\b((alloc::[A-Za-z0-9_]+::)?(Vec|String|VecDeque|Box|Rc|Arc|RefCell|Cell|HashMap|HashSet|BTreeMap|BTreeSet|Mutex|RwLock))\b[^)]*\)\s*(?:->\s*[^\\{;]+)?\s*\{' \
    "${TMPDIR}/src/kernel" >/dev/null
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_tree

  case "${CASE}" in
    abi-export-reference-types-fails)
      printf '\n#[no_mangle]\npub unsafe extern "C" fn bad_ref(value: &u8) -> usize { *value as usize }\n' \
        >>"${TMPDIR}/src/kernel/klib/memory/mod.rs"
      expect_failure "reference type in ABI export" check_no_references
      ;;
    abi-export-slice-or-str-fails)
      printf '\n#[no_mangle]\npub unsafe extern "C" fn bad_slice(value: &[u8]) -> usize { value.len() }\n' \
        >>"${TMPDIR}/src/kernel/klib/string/mod.rs"
      expect_failure "slice in ABI export" check_no_slices_or_str
      ;;
    abi-export-tuple-fails)
      printf '\n#[no_mangle]\npub unsafe extern "C" fn bad_tuple(pair: (u8, u8)) -> (u16, u16) { (pair.0 as u16, pair.1 as u16) }\n' \
        >>"${TMPDIR}/src/kernel/klib/string/mod.rs"
      expect_failure "tuple in ABI export" check_no_tuples
      ;;
    abi-export-unrepr-user-type-fails)
      printf '\nstruct RawPair {\n    first: u8,\n    second: u8,\n}\n\n#[no_mangle]\npub unsafe extern "C" fn bad_unrepr(pair: RawPair) -> u8 { pair.first }\n' \
        >>"${TMPDIR}/src/kernel/klib/memory/mod.rs"
      expect_failure "unrepr user type in ABI export" check_no_unrepr_user_type
      ;;
    abi-export-trait-object-fails)
      printf '\n#[no_mangle]\npub unsafe extern "C" fn bad_trait(obj: &dyn core::fmt::Display) -> usize {\n    let _ = obj;\n    0\n}\n' \
        >>"${TMPDIR}/src/kernel/klib/string/mod.rs"
      expect_failure "trait object in ABI export" check_no_trait_objects
      ;;
    abi-export-generic-fn-fails)
      printf '\n#[no_mangle]\npub unsafe extern "C" fn bad_generic<T>(value: T) -> usize { core::mem::size_of::<T>() + value as usize }\n' \
        >>"${TMPDIR}/src/kernel/klib/memory/mod.rs"
      expect_failure "generic function in ABI export" check_no_generic_exports
      ;;
    abi-export-option-result-fails)
      printf '\n#[no_mangle]\npub unsafe extern "C" fn bad_option(result: Option<u8>, status: Result<u8, u8>) -> Option<u8> { result }\n' \
        >>"${TMPDIR}/src/kernel/klib/string/mod.rs"
      expect_failure "Option/Result in ABI export" check_no_option_result
      ;;
    abi-export-allocator-type-fails)
      printf '\n#[no_mangle]\npub unsafe extern "C" fn bad_alloc(items: Vec<u8>) -> usize { items.len() }\n' \
        >>"${TMPDIR}/src/kernel/klib/memory/mod.rs"
      expect_failure "allocator-backed type in ABI export" check_no_allocator_types
      ;;
    *) die "unknown case: ${CASE}" ;;
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
  describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  run_case
}

main "$@"
