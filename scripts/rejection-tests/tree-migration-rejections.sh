#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
missing-required-tree-artifact-fails
legacy-kmain-path-fails
legacy-string-facade-path-fails
legacy-memory-facade-path-fails
legacy-vga-facade-path-fails
legacy-types-root-path-fails
legacy-port-helper-path-fails
EOF
}

describe_case() {
  case "$1" in
    missing-required-tree-artifact-fails) printf '%s\n' "rejects missing required future tree artifacts" ;;
    legacy-kmain-path-fails) printf '%s\n' "rejects legacy core entry peer path under src/kernel" ;;
    legacy-string-facade-path-fails) printf '%s\n' "rejects legacy string helper facade path" ;;
    legacy-memory-facade-path-fails) printf '%s\n' "rejects legacy memory helper facade path" ;;
    legacy-vga-facade-path-fails) printf '%s\n' "rejects legacy VGA driver facade path" ;;
    legacy-types-root-path-fails) printf '%s\n' "rejects legacy types root path" ;;
    legacy-port-helper-path-fails) printf '%s\n' "rejects legacy machine helper path under types" ;;
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
  mkdir -p "${TMPDIR}/src/kernel"/{core,services,types,klib/string,klib/memory,drivers/vga_text,machine}

  cat >"${TMPDIR}/src/kernel.rs" <<'EOF'
pub mod core;
EOF

cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
pub fn kmain() {}
EOF

  cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
pub fn init() {}
EOF

  cat >"${TMPDIR}/src/kernel/core/panic.rs" <<'EOF'
pub fn panic_handler() {}
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

  cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn print() {}
EOF

  return 0
}

required_tree_artifacts() {
  cat <<'EOF'
src/kernel.rs
src/kernel/core/entry.rs
src/kernel/core/init.rs
src/kernel/core/panic.rs
src/kernel/machine/port.rs
src/kernel/types/range.rs
src/kernel/types/screen.rs
src/kernel/klib/string/mod.rs
src/kernel/klib/string/imp.rs
src/kernel/klib/memory/mod.rs
src/kernel/klib/memory/imp.rs
src/kernel/drivers/vga_text/mod.rs
src/kernel/drivers/vga_text/writer.rs
src/kernel/services/console.rs
EOF
}

legacy_helper_type_paths() {
  cat <<'EOF'
src/kernel/kmain.rs
src/kernel/string.rs
src/kernel/memory.rs
src/kernel/vga.rs
src/kernel/types.rs
src/kernel/types/port.rs
src/kernel/kmain/logic_impl.rs
src/kernel/string/string_impl.rs
src/kernel/memory/memory_impl.rs
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

check_legacy_paths_absent() {
  local path
  while IFS= read -r path; do
    if [[ -e "${TMPDIR}/${path}" ]]; then
      return 1
    fi
  done < <(legacy_helper_type_paths)

  return 0
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_target_tree

  case "${CASE}" in
    missing-required-tree-artifact-fails)
      rm -f "${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "missing required future artifact" check_required_artifacts_exist
      ;;
    legacy-kmain-path-fails)
      cat >"${TMPDIR}/src/kernel/kmain.rs" <<'EOF'
pub fn kmain() {}
EOF
      expect_failure "legacy kmain path" check_legacy_paths_absent
      ;;
    legacy-string-facade-path-fails)
      cat >"${TMPDIR}/src/kernel/string.rs" <<'EOF'
pub fn strlen() {}
EOF
      expect_failure "legacy string facade path" check_legacy_paths_absent
      ;;
    legacy-memory-facade-path-fails)
      cat >"${TMPDIR}/src/kernel/memory.rs" <<'EOF'
pub fn memcpy() {}
EOF
      expect_failure "legacy memory facade path" check_legacy_paths_absent
      ;;
    legacy-vga-facade-path-fails)
      cat >"${TMPDIR}/src/kernel/vga.rs" <<'EOF'
pub fn vga_puts() {}
EOF
      expect_failure "legacy VGA facade path" check_legacy_paths_absent
      ;;
    legacy-types-root-path-fails)
      cat >"${TMPDIR}/src/kernel/types.rs" <<'EOF'
pub struct Port(pub u16);
EOF
      expect_failure "legacy types root path" check_legacy_paths_absent
      ;;
    legacy-port-helper-path-fails)
      mkdir -p "${TMPDIR}/src/kernel/types"
      cat >"${TMPDIR}/src/kernel/types/port.rs" <<'EOF'
#[repr(transparent)]
pub struct LegacyPort(pub u16);
EOF
      expect_failure "legacy port helper path" check_legacy_paths_absent
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
