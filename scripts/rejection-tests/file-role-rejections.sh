#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
top-level-peer-file-fails
facade-peer-shape-fails
orphan-leaf-location-fails
cross-facade-leaf-import-fails
unknown-role-file-fails
mixed-facade-and-leaf-shape-fails
EOF
}

describe_case() {
  case "$1" in
    top-level-peer-file-fails) printf '%s\n' "rejects top-level Rust peer files under src/kernel" ;;
    facade-peer-shape-fails) printf '%s\n' "rejects peer subsystem facade files beside subsystem directories" ;;
    orphan-leaf-location-fails) printf '%s\n' "rejects private leaves outside owning subsystem paths" ;;
    cross-facade-leaf-import-fails) printf '%s\n' "rejects facade importing another subsystem's private leaf" ;;
    unknown-role-file-fails) printf '%s\n' "rejects unknown file roles in kernel tree" ;;
    mixed-facade-and-leaf-shape-fails) printf '%s\n' "rejects mixing facade and leaf role shapes in one subsystem layout" ;;
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

  mkdir -p "${TMPDIR}/src/kernel"/{core,drivers/vga_text,klib/string,klib/memory,machine,services,types}

  cat >"${TMPDIR}/src/kernel.rs" <<'EOF'
pub mod kernel;
EOF
  for layer in core drivers klib machine services types; do
    printf 'pub mod placeholder;\n' >"${TMPDIR}/src/kernel/${layer}/mod.rs"
  done

  cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
pub fn kmain() {}
EOF
  cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
pub fn init() {}
EOF
  cat >"${TMPDIR}/src/kernel/core/panic.rs" <<'EOF'
pub fn halt_forever() -> ! {
    loop {}
}
EOF
  cat >"${TMPDIR}/src/kernel/machine/port.rs" <<'EOF'
#[repr(transparent)]
pub struct Port(u16);
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
#[path = "imp.rs"]
mod imp;
EOF
  cat >"${TMPDIR}/src/kernel/klib/string/imp.rs" <<'EOF'
pub unsafe fn string_len(_ptr: *const u8) -> usize {
    0
}
EOF
  cat >"${TMPDIR}/src/kernel/klib/memory/mod.rs" <<'EOF'
#[path = "imp.rs"]
mod imp;
EOF
  cat >"${TMPDIR}/src/kernel/klib/memory/imp.rs" <<'EOF'
pub unsafe fn memory_copy(_dst: *mut u8, _src: *const u8, _len: usize) -> *mut u8 {
    _dst
}
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

check_kernel_root_is_lone_top_level_rs() {
  local peers
  [[ -f "${TMPDIR}/src/kernel.rs" ]] || return 1
  peers="$(find "${TMPDIR}/src/kernel" -mindepth 1 -maxdepth 1 -type f -name '*.rs' -printf '%f\n' | sort)"
  [[ -n "${peers}" ]] && [[ "${peers}" == "kernel.rs" ]]
}

check_subsystem_facade_shapes_valid() {
  [[ -f "${TMPDIR}/src/kernel/klib/string/mod.rs" ]] || return 1
  [[ -f "${TMPDIR}/src/kernel/klib/string/imp.rs" ]] || return 1
  [[ -f "${TMPDIR}/src/kernel/klib/memory/mod.rs" ]] || return 1
  [[ -f "${TMPDIR}/src/kernel/klib/memory/imp.rs" ]] || return 1
  [[ -f "${TMPDIR}/src/kernel/drivers/vga_text/mod.rs" ]] || return 1
  [[ -f "${TMPDIR}/src/kernel/drivers/vga_text/writer.rs" ]] || return 1
  [[ -f "${TMPDIR}/src/kernel/services/console.rs" ]] || return 1
  [[ ! -f "${TMPDIR}/src/kernel/string.rs" ]] || return 1
  [[ ! -f "${TMPDIR}/src/kernel/memory.rs" ]] || return 1
  [[ ! -f "${TMPDIR}/src/kernel/vga_text.rs" ]] || return 1
  [[ ! -f "${TMPDIR}/src/kernel/klib/string.rs" ]] || return 1
  [[ ! -f "${TMPDIR}/src/kernel/klib/memory.rs" ]] || return 1
  [[ ! -f "${TMPDIR}/src/kernel/drivers/vga_text.rs" ]] || return 1
  return 0
}

check_private_leaves_owned() {
  local bad=()
  local path

  for path in \
    "${TMPDIR}/src/kernel/klib/string/imp.rs" \
    "${TMPDIR}/src/kernel/klib/memory/imp.rs" \
    "${TMPDIR}/src/kernel/drivers/vga_text/writer.rs"; do
    [[ -f "${path}" ]] || bad+=("${path#${TMPDIR}/}")
  done

  while IFS= read -r -d '' path; do
    case "${path#${TMPDIR}/}" in
      src/kernel/klib/string/imp.rs|src/kernel/klib/memory/imp.rs|src/kernel/drivers/vga_text/writer.rs) ;;
      *)
        bad+=("${path#${TMPDIR}/} (unexpected private leaf)")
        ;;
    esac
  done < <(find "${TMPDIR}/src/kernel" -type f \( -name 'imp.rs' -o -name 'writer.rs' \) -print0)

  [[ "${#bad[@]}" -eq 0 ]]
}

check_private_leaf_imports_local() {
  local offenders
  offenders="$(
    find "${TMPDIR}/src/kernel" -type f -name '*.rs' -print0 |
      xargs -0 rg -n '\#\[path[[:space:]]*=[[:space:]]*\"[^\"]*(string|memory|vga_text)/(imp|writer)\.rs\"|^\s*mod\s+(imp|writer)\s*;|\buse\s+crate::kernel::(?:klib|drivers)::(?:string|memory|vga_text)::(?:imp|writer)\b|\bcrate::kernel::(?:klib|drivers)::(?:string|memory|vga_text)::(?:imp|writer)\b' -P -S 2>/dev/null |
      grep -vE '^.*/src/kernel/(klib/string/mod\.rs|klib/memory/mod\.rs|drivers/vga_text/mod\.rs):' || true
  )"
  [[ -z "${offenders}" ]]
}

check_unknown_roles() {
  local path
  local rel
  local offenders=()

  while IFS= read -r -d '' path; do
    rel="${path#${TMPDIR}/}"
    case "${rel}" in
      src/kernel.rs) ;;
      src/kernel/core/mod.rs) ;;
      src/kernel/core/entry.rs) ;;
      src/kernel/core/init.rs) ;;
      src/kernel/core/panic.rs) ;;
      src/kernel/drivers/mod.rs) ;;
      src/kernel/drivers/vga_text/mod.rs) ;;
      src/kernel/drivers/vga_text/writer.rs) ;;
      src/kernel/klib/mod.rs) ;;
      src/kernel/klib/string/mod.rs) ;;
      src/kernel/klib/string/imp.rs) ;;
      src/kernel/klib/memory/mod.rs) ;;
      src/kernel/klib/memory/imp.rs) ;;
      src/kernel/machine/mod.rs) ;;
      src/kernel/machine/port.rs) ;;
      src/kernel/services/mod.rs) ;;
      src/kernel/services/console.rs) ;;
      src/kernel/types/*.rs) ;;
      *) offenders+=("${rel}") ;;
    esac
  done < <(find "${TMPDIR}/src/kernel" -type f -name '*.rs' -print0)

  [[ "${#offenders[@]}" -eq 0 ]]
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_tree

  case "${CASE}" in
    top-level-peer-file-fails)
      printf '\npub fn bad() {}\n' >"${TMPDIR}/src/kernel/extra.rs"
      expect_failure "top-level peer file" check_kernel_root_is_lone_top_level_rs
      ;;
    facade-peer-shape-fails)
      printf '\npub fn bad() {}\n' >"${TMPDIR}/src/kernel/string.rs"
      expect_failure "facade peer file" check_subsystem_facade_shapes_valid
      ;;
    orphan-leaf-location-fails)
      printf '\npub fn bad() {}\n' >"${TMPDIR}/src/kernel/services/imp.rs"
      expect_failure "orphan private leaf location" check_private_leaves_owned
      ;;
    cross-facade-leaf-import-fails)
      printf '\nuse crate::kernel::klib::string::imp;\n' >>"${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "cross-facade leaf import" check_private_leaf_imports_local
      ;;
    unknown-role-file-fails)
      printf '\npub fn telemetry() {}\n' >"${TMPDIR}/src/kernel/services/telemetry.rs"
      expect_failure "unknown role file" check_unknown_roles
      ;;
    mixed-facade-and-leaf-shape-fails)
      mkdir -p "${TMPDIR}/src/kernel/klib/memory"
      printf '\npub fn legacy_memory() {}\n' >"${TMPDIR}/src/kernel/klib/memory.rs"
      expect_failure "mixed facade and leaf shape" check_subsystem_facade_shapes_valid
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
