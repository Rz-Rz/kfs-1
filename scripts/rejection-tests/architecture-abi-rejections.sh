#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
extern-block-outside-core-entry-fails
services-abi-marker-fails
driver-abi-marker-fails
leaf-abi-marker-fails
allowed-toolchain-boundary-marker-pass
forbidden-abi-signature-form-fails
EOF
}

describe_case() {
  case "$1" in
    extern-block-outside-core-entry-fails) printf '%s\n' "rejects ABI markers outside approved boundaries" ;;
    services-abi-marker-fails) printf '%s\n' "rejects ABI markers in services" ;;
    driver-abi-marker-fails) printf '%s\n' "rejects ABI markers in drivers" ;;
    leaf-abi-marker-fails) printf '%s\n' "rejects ABI markers in leaf files" ;;
    allowed-toolchain-boundary-marker-pass) printf '%s\n' "keeps ABI markers on toolchain boundaries" ;;
    forbidden-abi-signature-form-fails) printf '%s\n' "rejects forbidden ABI signature forms" ;;
    *) return 1 ;;
  esac
}

die() { echo "error: $*" >&2; exit 2; }
cleanup() {
  if [[ -n "${TMPDIR}" ]]; then
    rm -rf "${TMPDIR}"
  fi
}
trap cleanup EXIT

make_tree() {
  TMPDIR="$(mktemp -d)"
  mkdir -p "${TMPDIR}/src/kernel/core" "${TMPDIR}/src/kernel/klib/string" "${TMPDIR}/src/kernel/klib/memory" "${TMPDIR}/src/kernel/services" "${TMPDIR}/src/kernel/drivers/vga_text" "${TMPDIR}/src/arch/i386"
  cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
extern "C" {
    static kernel_start: u8;
}
#[no_mangle]
pub extern "C" fn kmain() -> ! { loop {} }
EOF
  cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
pub fn init() {}
EOF
  cat >"${TMPDIR}/src/kernel/klib/string/mod.rs" <<'EOF'
#[no_mangle]
pub unsafe extern "C" fn kfs_strlen(ptr: *const u8) -> usize { let _ = ptr; 0 }
EOF
  cat >"${TMPDIR}/src/kernel/klib/memory/mod.rs" <<'EOF'
#[no_mangle]
pub unsafe extern "C" fn kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 { let _ = (src, len); dst }
EOF
  cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn console_write() {}
EOF
  cat >"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs" <<'EOF'
pub fn write_cell() {}
EOF
  cat >"${TMPDIR}/src/kernel/klib/string/imp.rs" <<'EOF'
pub unsafe fn imp(_ptr: *const u8) -> usize { 0 }
EOF
  cat >"${TMPDIR}/src/arch/i386/entry.rs" <<'EOF'
#[no_mangle]
pub unsafe extern "C" fn _start() -> ! {
    loop {}
}
EOF
}

expect_failure() {
  local description="$1"; shift
  if "$@"; then
    echo "FAIL ${CASE}: ${description} unexpectedly passed"
    return 1
  fi
  echo "PASS ${CASE}: ${description} rejected"
}

check_abi_markers_outside_approved_boundaries() {
  local offenders
  offenders="$(
    find "${TMPDIR}/src" -type f \( -name '*.rs' -o -name '*.asm' \) -print0 |
      xargs -0 rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' -S 2>/dev/null |
      grep -vE '^.*/src/kernel/core/entry\.rs:|^.*/src/kernel/klib/(string|memory)/mod\.rs:|^.*/src/arch/.+/.+\.rs:' || true
  )"

  [[ -z "${offenders}" ]]
}

check_no_abi_in_services() {
  ! rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' "${TMPDIR}/src/kernel/services" >/dev/null
}

check_no_abi_in_drivers() {
  ! rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' "${TMPDIR}/src/kernel/drivers" >/dev/null
}

check_no_abi_in_leaves() {
  ! find "${TMPDIR}/src/kernel" -type f \( -name 'imp.rs' -o -name 'writer.rs' -o -name '*_impl.rs' -o -name 'logic_impl.rs' \) -print0 |
    xargs -0 rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' -S 2>/dev/null >/dev/null
}

check_stable_abi_signatures() {
  ! rg -n 'pub[[:space:]]+.*extern[[:space:]]+"C"[[:space:]]+fn.*(&[^,)]*|\[[^]]*\]|str\b|Option<|Result<|dyn[[:space:]]|Vec<|String\b|impl[[:space:]])' \
    "${TMPDIR}/src/kernel/core/entry.rs" "${TMPDIR}/src/kernel/klib/string/mod.rs" "${TMPDIR}/src/kernel/klib/memory/mod.rs" >/dev/null
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_tree
  case "${CASE}" in
    extern-block-outside-core-entry-fails)
      printf '\nextern \"C\" { fn leak(); }\n' >>"${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "ABI marker outside approved boundaries" check_abi_markers_outside_approved_boundaries
      ;;
    services-abi-marker-fails)
      printf '\n#[no_mangle]\npub extern \"C\" fn leaked() {}\n' >>"${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "ABI marker in services" check_no_abi_in_services
      ;;
    driver-abi-marker-fails)
      printf '\n#[no_mangle]\npub extern \"C\" fn leaked() {}\n' >>"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs"
      expect_failure "ABI marker in drivers" check_no_abi_in_drivers
      ;;
    leaf-abi-marker-fails)
      printf '\n#[no_mangle]\npub extern \"C\" fn leaked() {}\n' >>"${TMPDIR}/src/kernel/klib/string/imp.rs"
      expect_failure "ABI marker in leaf" check_no_abi_in_leaves
      ;;
    allowed-toolchain-boundary-marker-pass)
      if ! check_abi_markers_outside_approved_boundaries; then
        echo "FAIL ${CASE}: marker in allowed boundaries still flagged unexpectedly"
        return 1
      fi
      echo "PASS ${CASE}: marker in toolchain boundary allowed"
      ;;
    forbidden-abi-signature-form-fails)
      printf '\n#[no_mangle]\npub unsafe extern \"C\" fn bad(arg: &str) -> usize { let _ = arg; 0 }\n' >>"${TMPDIR}/src/kernel/klib/string/mod.rs"
      expect_failure "forbidden ABI signature form" check_stable_abi_signatures
      ;;
    *) die "unknown case: ${CASE}" ;;
  esac
}

main() {
  if [[ "${ARCH}" == "--list" ]]; then list_cases; return 0; fi
  if [[ "${ARCH}" == "--description" ]]; then describe_case "${CASE}"; return 0; fi
  describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  run_case
}

main "$@"
