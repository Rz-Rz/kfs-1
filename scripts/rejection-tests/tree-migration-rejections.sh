#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
missing-required-tree-artifact-fails
EOF
}

describe_case() {
  case "$1" in
    missing-required-tree-artifact-fails) printf '%s\n' "rejects missing required future tree artifacts" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

cleanup() {
  if [[ -n "${TMPDIR}" && -d "${TMPDIR}" ]]; then
    rm -rf -- "${TMPDIR}"
  fi
}

trap cleanup EXIT

make_target_tree() {
  TMPDIR="$(mktemp -d)"
  mkdir -p "${TMPDIR}/src/kernel"/{core,services,types,klib/string,klib/memory,drivers/vga_text,drivers/serial,machine}
  mkdir -p "${TMPDIR}/src/freestanding"

  cat >"${TMPDIR}/src/main.rs" <<'EOF'
pub mod kernel;
EOF

  cat >"${TMPDIR}/src/kernel/mod.rs" <<'EOF'
pub mod core;
pub mod drivers;
pub mod klib;
pub mod machine;
pub mod services;
pub mod types;
EOF

cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
pub fn kmain() {}
EOF

  cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
pub fn init() {}
EOF

  cat >"${TMPDIR}/src/freestanding/mod.rs" <<'EOF'
mod panic;
mod section_markers;
EOF

  cat >"${TMPDIR}/src/freestanding/panic.rs" <<'EOF'
pub fn panic_handler() {}
EOF

  cat >"${TMPDIR}/src/freestanding/section_markers.rs" <<'EOF'
#[no_mangle]
static KFS_RODATA_MARKER: [u8; 8] = *b"KFSRODAT";
EOF

  cat >"${TMPDIR}/src/kernel/machine/port.rs" <<'EOF'
#[repr(transparent)]
pub struct Port(pub u16);
EOF

  cat >"${TMPDIR}/src/kernel/types/range.rs" <<'EOF'
#[repr(C)]
pub struct KernelRange {
    pub start: usize,
    pub end: usize,
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

  cat >"${TMPDIR}/src/kernel/klib/string/mod.rs" <<'EOF'
pub mod imp;
EOF

  cat >"${TMPDIR}/src/kernel/klib/string/imp.rs" <<'EOF'
pub fn strlen(_s: *const u8) -> usize { 0 }
EOF

  cat >"${TMPDIR}/src/kernel/klib/memory/mod.rs" <<'EOF'
pub mod imp;
EOF

  cat >"${TMPDIR}/src/kernel/klib/memory/imp.rs" <<'EOF'
pub unsafe fn memcpy(_dst: *mut u8, _src: *const u8, _len: usize) -> *mut u8 { _dst }
EOF

  cat >"${TMPDIR}/src/kernel/drivers/vga_text/mod.rs" <<'EOF'
pub mod writer;
EOF

  cat >"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs" <<'EOF'
pub fn write() {}
EOF

  cat >"${TMPDIR}/src/kernel/drivers/serial/mod.rs" <<'EOF'
pub fn initialize() {}
EOF

  cat >"${TMPDIR}/src/kernel/services/diagnostics.rs" <<'EOF'
pub fn write_line() {}
EOF

  cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn print() {}
EOF

  return 0
}

required_tree_artifacts() {
  cat <<'EOF'
src/main.rs
src/freestanding/mod.rs
src/freestanding/panic.rs
src/freestanding/section_markers.rs
src/kernel/mod.rs
src/kernel/core/entry.rs
src/kernel/core/init.rs
src/kernel/machine/port.rs
src/kernel/types/range.rs
src/kernel/types/screen.rs
src/kernel/klib/string/mod.rs
src/kernel/klib/string/imp.rs
src/kernel/klib/memory/mod.rs
src/kernel/klib/memory/imp.rs
src/kernel/drivers/serial/mod.rs
src/kernel/drivers/vga_text/mod.rs
src/kernel/drivers/vga_text/writer.rs
src/kernel/services/diagnostics.rs
src/kernel/services/console.rs
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

check_required_artifacts_exist() {
  local missing=0

  while IFS= read -r path; do
    [[ -f "${TMPDIR}/${path}" ]] || missing=1
  done < <(required_tree_artifacts)

  [[ "${missing}" -eq 0 ]]
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_target_tree

  case "${CASE}" in
    missing-required-tree-artifact-fails)
      rm -f "${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "missing required future artifact" check_required_artifacts_exist
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
