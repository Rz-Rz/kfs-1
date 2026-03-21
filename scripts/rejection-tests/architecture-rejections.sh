#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
new-top-level-kernel-peer-file-fails
disallowed-first-level-layer-fails
types-abi-export-fails
private-leaf-import-fails
raw-hardware-in-services-fails
per-file-kernel-build-fails
exports-allowlist-drift-fails
EOF
}

describe_case() {
  case "$1" in
    new-top-level-kernel-peer-file-fails) printf '%s\n' "rejects a new top-level kernel peer file" ;;
    disallowed-first-level-layer-fails) printf '%s\n' "rejects a disallowed first-level kernel layer" ;;
    types-abi-export-fails) printf '%s\n' "rejects ABI exports in the types layer" ;;
    private-leaf-import-fails) printf '%s\n' "rejects private leaf imports outside the owning facade" ;;
    raw-hardware-in-services-fails) printf '%s\n' "rejects raw hardware access in services" ;;
    per-file-kernel-build-fails) printf '%s\n' "rejects per-file kernel compilation in the Makefile" ;;
    exports-allowlist-drift-fails) printf '%s\n' "rejects unexpected export allowlist drift" ;;
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

make_target_tree() {
  TMPDIR="$(mktemp -d)"

  mkdir -p "${TMPDIR}/src/kernel"/{core,machine,types,klib/string,klib/memory,drivers/vga_text,services}
  mkdir -p "${TMPDIR}/scripts/architecture-tests/fixtures"

  cat >"${TMPDIR}/src/kernel.rs" <<'EOF'
pub mod kernel;
EOF

  cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
pub fn kmain() {}
EOF

  cat >"${TMPDIR}/src/kernel/machine/port.rs" <<'EOF'
#[repr(transparent)]
pub struct Port(u16);
EOF

  cat >"${TMPDIR}/src/kernel/types/mod.rs" <<'EOF'
pub mod range;
EOF

  cat >"${TMPDIR}/src/kernel/types/range.rs" <<'EOF'
#[repr(C)]
pub struct KernelRange {
    start: usize,
    end: usize,
}
EOF

  cat >"${TMPDIR}/src/kernel/klib/string/mod.rs" <<'EOF'
#[path = "imp.rs"]
mod imp;
EOF

  cat >"${TMPDIR}/src/kernel/klib/string/imp.rs" <<'EOF'
pub unsafe fn string_len_impl(_ptr: *const u8) -> usize { 0 }
EOF

  cat >"${TMPDIR}/src/kernel/klib/memory/mod.rs" <<'EOF'
#[path = "imp.rs"]
mod imp;
EOF

  cat >"${TMPDIR}/src/kernel/klib/memory/imp.rs" <<'EOF'
pub unsafe fn memory_copy_impl(_dst: *mut u8, _src: *const u8, _len: usize) -> *mut u8 { _dst }
EOF

  cat >"${TMPDIR}/src/kernel/drivers/vga_text/mod.rs" <<'EOF'
#[path = "writer.rs"]
mod writer;
EOF

  cat >"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs" <<'EOF'
const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
EOF

  cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn console_write() {}
EOF

  cat >"${TMPDIR}/Makefile" <<'EOF'
rust_source_files := src/kernel.rs
EOF

  cat >"${TMPDIR}/scripts/architecture-tests/fixtures/exports.i386.allowlist" <<'EOF'
_start
kmain
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
  return 0
}

check_no_top_level_peer_files() {
  ! find "${TMPDIR}/src/kernel" -mindepth 1 -maxdepth 1 -type f -name '*.rs' | grep -q .
}

check_first_level_allowlist() {
  local expected actual
  expected="$(cat <<'EOF'
core
drivers
klib
machine
services
types
EOF
)"
  actual="$(find "${TMPDIR}/src/kernel" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)"
  [[ "${actual}" == "${expected}" ]]
}

check_no_types_abi_export() {
  ! rg -n '#\[no_mangle\]|extern[[:space:]]+"C"' "${TMPDIR}/src/kernel/types" >/dev/null
}

check_no_private_leaf_imports() {
  ! rg -n '#\[path = ".*(imp|writer)\.rs"\]' "${TMPDIR}/src/kernel" -g '*.rs' | grep -vE ':(#\[path = "imp\.rs"\]|#\[path = "writer\.rs"\])' >/dev/null
}

check_no_raw_hardware_in_services() {
  ! rg -n '0x[bB]8000|write_volatile|read_volatile|\binb\b|\boutb\b' "${TMPDIR}/src/kernel/services" >/dev/null
}

check_no_per_file_kernel_build() {
  ! rg -n 'src/kernel/\*\.rs|build/arch/\$\(arch\)/rust/%\.o: src/%\.rs' "${TMPDIR}/Makefile" >/dev/null
}

check_allowlist_exact() {
  local expected actual
  expected='_start
kmain'
  actual="$(sort -u "${TMPDIR}/scripts/architecture-tests/fixtures/exports.i386.allowlist")"
  [[ "${actual}" == "${expected}" ]]
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_target_tree

  case "${CASE}" in
    new-top-level-kernel-peer-file-fails)
      printf 'pub fn stray() {}\n' >"${TMPDIR}/src/kernel/stray.rs"
      expect_failure "top-level kernel peer file" check_no_top_level_peer_files
      ;;
    disallowed-first-level-layer-fails)
      mkdir -p "${TMPDIR}/src/kernel/experimental"
      expect_failure "disallowed first-level kernel layer" check_first_level_allowlist
      ;;
    types-abi-export-fails)
      printf '\n#[no_mangle]\npub extern "C" fn leaked() {}\n' >>"${TMPDIR}/src/kernel/types/range.rs"
      expect_failure "ABI export in types layer" check_no_types_abi_export
      ;;
    private-leaf-import-fails)
      printf '\n#[path = "../klib/string/imp.rs"]\nmod leaked_imp;\n' >>"${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "private leaf import outside owning facade" check_no_private_leaf_imports
      ;;
    raw-hardware-in-services-fails)
      printf '\nconst VGA_PTR: *mut u16 = 0xb8000 as *mut u16;\n' >>"${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "raw hardware access in services" check_no_raw_hardware_in_services
      ;;
    per-file-kernel-build-fails)
      printf '\nrust_source_files := $(wildcard src/kernel/*.rs)\n' >>"${TMPDIR}/Makefile"
      expect_failure "per-file kernel compilation" check_no_per_file_kernel_build
      ;;
    exports-allowlist-drift-fails)
      printf 'vga_puts\n' >>"${TMPDIR}/scripts/architecture-tests/fixtures/exports.i386.allowlist"
      expect_failure "export allowlist drift" check_allowlist_exact
      ;;
    *)
      die "unknown case: ${CASE}"
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

  describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  run_case
}

main "$@"
