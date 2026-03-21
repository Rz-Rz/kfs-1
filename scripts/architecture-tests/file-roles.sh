#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

LAYERS=("core" "drivers" "klib" "machine" "services" "types")

list_cases() {
  cat <<'EOF'
crate-root-is-lone-top-level-rs
kernel-top-level-directories-are-layers-only
layer-roots-are-mod-rs
subsystem-facade-shapes-are-valid
private-leaves-are-owned-and-located
private-leaf-imports-are-local
kernel-files-have-recognized-roles
EOF
}

describe_case() {
  case "$1" in
    crate-root-is-lone-top-level-rs) printf '%s\n' "src/main.rs is the freestanding root and src/kernel/mod.rs is the only top-level Rust file under src/kernel" ;;
    kernel-top-level-directories-are-layers-only) printf '%s\n' "kernel top-level directories match the target layer set" ;;
    layer-roots-are-mod-rs) printf '%s\n' "each kernel layer has a mod.rs root" ;;
    subsystem-facade-shapes-are-valid) printf '%s\n' "subsystem facades are in allowed shapes and locations" ;;
    private-leaves-are-owned-and-located) printf '%s\n' "private leaves live only in approved owning subsystem paths" ;;
    private-leaf-imports-are-local) printf '%s\n' "private leaves are imported only by owning facades" ;;
    kernel-files-have-recognized-roles) printf '%s\n' "every Rust file in src/kernel has a known architecture role" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

assert_crate_root_is_lone_top_level_rs() {
  local peers

  [[ -f "${REPO_ROOT}/src/main.rs" ]] || {
    echo "FAIL ${CASE}: missing src/main.rs"
    return 1
  }

  [[ -f "${REPO_ROOT}/src/kernel/mod.rs" ]] || {
    echo "FAIL ${CASE}: missing src/kernel/mod.rs"
    return 1
  }

  peers="$(find "${REPO_ROOT}/src/kernel" -mindepth 1 -maxdepth 1 -type f -name '*.rs' -printf '%f\n' | sort)"
  if [[ -n "${peers}" ]] && [[ "${peers}" != "mod.rs" ]]; then
    echo "FAIL ${CASE}: top-level Rust peer files must not exist under src/kernel"
    printf '%s\n' "${peers}"
    return 1
  fi

  echo "PASS ${CASE}: src/main.rs and src/kernel/mod.rs are the only top-level Rust roots"
}

assert_top_level_is_layers_only() {
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

  actual="$(find "${REPO_ROOT}/src/kernel" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)"

  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL ${CASE}: kernel top-level directories are not exactly the layer set"
    printf 'expected:\n%s\n' "${expected}"
    printf 'actual:\n%s\n' "${actual}"
    return 1
  fi

  echo "PASS ${CASE}: kernel top-level directories are exactly expected layers"
}

assert_layer_roots_are_mod_rs() {
  local layer
  local missing=()
  local root

  for layer in "${LAYERS[@]}"; do
    root="${REPO_ROOT}/src/kernel/${layer}/mod.rs"
    [[ -f "${root}" ]] || missing+=("${root#${REPO_ROOT}/}")
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "FAIL ${CASE}: missing layer root mod.rs files"
    printf '%s\n' "${missing[@]}"
    return 1
  fi

  echo "PASS ${CASE}: all layer roots are explicit mod.rs files"
}

assert_subsystem_facade_shapes_are_valid() {
  local offenders=()

  [[ -f "${REPO_ROOT}/src/kernel/core/entry.rs" ]] || offenders+=("src/kernel/core/entry.rs")
  [[ -f "${REPO_ROOT}/src/kernel/core/init.rs" ]] || offenders+=("src/kernel/core/init.rs")
  [[ -f "${REPO_ROOT}/src/kernel/machine/port.rs" ]] || offenders+=("src/kernel/machine/port.rs")
  [[ -f "${REPO_ROOT}/src/kernel/types/range.rs" ]] || offenders+=("src/kernel/types/range.rs")
  [[ -f "${REPO_ROOT}/src/kernel/types/screen.rs" ]] || offenders+=("src/kernel/types/screen.rs")
  [[ -f "${REPO_ROOT}/src/kernel/services/console.rs" ]] || offenders+=("src/kernel/services/console.rs")
  [[ -f "${REPO_ROOT}/src/kernel/services/diagnostics.rs" ]] || offenders+=("src/kernel/services/diagnostics.rs")

  # Facades with private leaves must be directories with a mod.rs and owned leaf.
  [[ -f "${REPO_ROOT}/src/kernel/klib/string/mod.rs" ]] || offenders+=("src/kernel/klib/string/mod.rs")
  [[ -f "${REPO_ROOT}/src/kernel/klib/string/imp.rs" ]] || offenders+=("src/kernel/klib/string/imp.rs")
  [[ -f "${REPO_ROOT}/src/kernel/klib/memory/mod.rs" ]] || offenders+=("src/kernel/klib/memory/mod.rs")
  [[ -f "${REPO_ROOT}/src/kernel/klib/memory/imp.rs" ]] || offenders+=("src/kernel/klib/memory/imp.rs")
  [[ -f "${REPO_ROOT}/src/kernel/drivers/serial/mod.rs" ]] || offenders+=("src/kernel/drivers/serial/mod.rs")
  [[ -f "${REPO_ROOT}/src/kernel/drivers/keyboard/mod.rs" ]] || offenders+=("src/kernel/drivers/keyboard/mod.rs")
  [[ -f "${REPO_ROOT}/src/kernel/drivers/keyboard/imp.rs" ]] || offenders+=("src/kernel/drivers/keyboard/imp.rs")
  [[ -f "${REPO_ROOT}/src/kernel/drivers/vga_text/mod.rs" ]] || offenders+=("src/kernel/drivers/vga_text/mod.rs")
  [[ -f "${REPO_ROOT}/src/kernel/drivers/vga_text/writer.rs" ]] || offenders+=("src/kernel/drivers/vga_text/writer.rs")

  if [[ "${#offenders[@]}" -gt 0 ]]; then
    echo "FAIL ${CASE}: invalid subsystem facade shape or missing required target facade/leaf files"
    printf '%s\n' "${offenders[@]}"
    return 1
  fi

  echo "PASS ${CASE}: subsystem facades and leaves use valid target shapes"
}

assert_private_leaves_are_owned_and_located() {
  local allowed=(
    "src/kernel/klib/string/imp.rs"
    "src/kernel/klib/memory/imp.rs"
    "src/kernel/drivers/keyboard/imp.rs"
    "src/kernel/drivers/vga_text/writer.rs"
  )
  local allowed_set
  local leaf
  local offenders=()
  local leaf_rel

  # shellcheck disable=SC2086
  allowed_set="$(printf '%s\n' "${allowed[@]}")"

  for leaf in "${allowed[@]}"; do
    [[ -f "${REPO_ROOT}/${leaf}" ]] || offenders+=("${leaf}")
  done

  while IFS= read -r -d '' leaf_path; do
    leaf_rel="${leaf_path#${REPO_ROOT}/}"
    if ! grep -Fxq "${leaf_rel}" <<<"${allowed_set}"; then
      offenders+=("${leaf_rel} (unexpected private-leaf name/location)")
    fi
  done < <(find "${REPO_ROOT}/src/kernel" -type f \( -name 'imp.rs' -o -name 'writer.rs' \) -print0)

  if [[ "${#offenders[@]}" -gt 0 ]]; then
    echo "FAIL ${CASE}: private leaves are missing or in non-owning paths"
    printf '%s\n' "${offenders[@]}"
    return 1
  fi

  echo "PASS ${CASE}: private leaves exist only in owning facade paths"
}

assert_private_leaf_imports_are_local() {
  local offenders

  offenders="$(
    find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0 |
      xargs -0 rg -n '\#\[path[[:space:]]*=[[:space:]]*"[^\"]*(string|memory|keyboard|vga_text)/(imp|writer)\.rs"|^\s*mod\s+(imp|writer)\s*;|\buse\s+crate::kernel::(?:klib|drivers)::(?:string|memory|keyboard|vga_text)::(?:imp|writer)\b|\bcrate::kernel::(?:klib|drivers)::(?:string|memory|keyboard|vga_text)::(?:imp|writer)\b' -P -S 2>/dev/null |
      grep -vE '^.*/src/kernel/(klib/string/mod\.rs|klib/memory/mod\.rs|drivers/keyboard/mod\.rs|drivers/vga_text/mod\.rs):' || true
  )"

  if [[ -n "${offenders}" ]]; then
    echo "FAIL ${CASE}: private leaf imports referenced outside owning subsystem files"
    printf '%s\n' "${offenders}"
    return 1
  fi

  echo "PASS ${CASE}: private leaf imports are local to owning facades"
}

assert_kernel_files_have_recognized_roles() {
  local offenders=()
  local rel
  local path

  while IFS= read -r -d '' path; do
    rel="${path#${REPO_ROOT}/}"
    case "${rel}" in
      src/main.rs) ;;
      src/kernel/mod.rs) ;;
      src/kernel/core/mod.rs) ;;
      src/kernel/core/entry.rs) ;;
      src/kernel/core/init.rs) ;;
      src/kernel/drivers/mod.rs) ;;
      src/kernel/drivers/serial/mod.rs) ;;
      src/kernel/drivers/keyboard/mod.rs) ;;
      src/kernel/drivers/keyboard/imp.rs) ;;
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
      src/kernel/services/diagnostics.rs) ;;
      src/kernel/types/mod.rs) ;;
      src/kernel/types/range.rs) ;;
      src/kernel/types/screen.rs) ;;
      src/kernel/types/*.rs) ;;
      *)
        offenders+=("${rel#src/kernel/}")
        ;;
    esac
  done < <(find "${REPO_ROOT}/src/kernel" -type f -name '*.rs' -print0)

  if [[ "${#offenders[@]}" -gt 0 ]]; then
    echo "FAIL ${CASE}: these files do not map to a known file-role"
    printf '%s\n' "${offenders[@]}"
    return 1
  fi

  echo "PASS ${CASE}: all Rust files in src/kernel are recognized roles"
}

run_case() {
  case "${CASE}" in
    crate-root-is-lone-top-level-rs) assert_crate_root_is_lone_top_level_rs ;;
    kernel-top-level-directories-are-layers-only) assert_top_level_is_layers_only ;;
    layer-roots-are-mod-rs) assert_layer_roots_are_mod_rs ;;
    subsystem-facade-shapes-are-valid) assert_subsystem_facade_shapes_are_valid ;;
    private-leaves-are-owned-and-located) assert_private_leaves_are_owned_and_located ;;
    private-leaf-imports-are-local) assert_private_leaf_imports_are_local ;;
    kernel-files-have-recognized-roles) assert_kernel_files_have_recognized_roles ;;
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

  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  run_case
}

main "$@"
