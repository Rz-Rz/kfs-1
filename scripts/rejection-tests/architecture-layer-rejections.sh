#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
layer-root-modrs-missing-fails
boot-calls-driver-directly-fails
core-inline-asm-fails
services-raw-hardware-fails
types-side-effect-fails
EOF
}

describe_case() {
  case "$1" in
    layer-root-modrs-missing-fails) printf '%s\n' "rejects missing layer mod.rs roots" ;;
    boot-calls-driver-directly-fails) printf '%s\n' "rejects boot asm calling driver or helper surfaces directly" ;;
    core-inline-asm-fails) printf '%s\n' "rejects inline asm in core" ;;
    services-raw-hardware-fails) printf '%s\n' "rejects raw hardware access in services" ;;
    types-side-effect-fails) printf '%s\n' "rejects side effects in types" ;;
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
  mkdir -p "${TMPDIR}/src/arch/i386"
  mkdir -p "${TMPDIR}/src/kernel"/{core,machine,types,klib,drivers,services}
  for layer in core machine types klib drivers services; do
    printf 'pub mod placeholder;\n' >"${TMPDIR}/src/kernel/${layer}/mod.rs"
  done
  cat >"${TMPDIR}/src/arch/i386/boot.asm" <<'EOF'
extern kmain
start:
    call kmain
EOF
  cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
pub fn kmain() {}
EOF
  cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
pub fn init() {}
EOF
  cat >"${TMPDIR}/src/kernel/core/panic.rs" <<'EOF'
pub fn halt_forever() -> ! { loop {} }
EOF
  cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn console_write() {}
EOF
  cat >"${TMPDIR}/src/kernel/types/screen.rs" <<'EOF'
#[repr(transparent)]
pub struct ColorCode(pub u8);
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

check_layer_modrs() {
  local layer
  for layer in core machine types klib drivers services; do
    [[ -f "${TMPDIR}/src/kernel/${layer}/mod.rs" ]] || return 1
  done
}

check_boot_only_kmain() {
  ! rg -n '^extern (vga_|kfs_strlen|kfs_strcmp|kfs_memcpy|kfs_memset)' "${TMPDIR}/src/arch/i386/boot.asm" >/dev/null &&
    ! rg -n 'call (?!kmain\b)[A-Za-z_][A-Za-z0-9_]*' -P "${TMPDIR}/src/arch/i386/boot.asm" >/dev/null
}

check_core_no_asm() {
  ! rg -n 'core::arch::asm!|\b(inb|outb)\b|0x[bB]8000|vga_(init|putc|puts)' "${TMPDIR}/src/kernel/core" >/dev/null
}

check_services_no_raw_hw() {
  ! rg -n 'core::arch::asm!|\b(inb|outb)\b|0x[bB]8000|write_volatile|read_volatile' "${TMPDIR}/src/kernel/services" >/dev/null
}

check_types_no_side_effects() {
  ! rg -n 'core::arch::asm!|\b(inb|outb)\b|write_volatile|read_volatile|extern[[:space:]]+"C"|#\[no_mangle\]' "${TMPDIR}/src/kernel/types" >/dev/null
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_tree
  case "${CASE}" in
    layer-root-modrs-missing-fails)
      rm -f "${TMPDIR}/src/kernel/services/mod.rs"
      expect_failure "missing layer mod.rs root" check_layer_modrs
      ;;
    boot-calls-driver-directly-fails)
      printf '\nextern vga_puts\n    call vga_puts\n' >>"${TMPDIR}/src/arch/i386/boot.asm"
      expect_failure "boot direct driver/helper call" check_boot_only_kmain
      ;;
    core-inline-asm-fails)
      printf '\nfn bad() { unsafe { core::arch::asm!(\"hlt\"); } }\n' >>"${TMPDIR}/src/kernel/core/init.rs"
      expect_failure "inline asm in core" check_core_no_asm
      ;;
    services-raw-hardware-fails)
      printf '\nconst VGA: *mut u16 = 0xb8000 as *mut u16;\n' >>"${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "raw hardware in services" check_services_no_raw_hw
      ;;
    types-side-effect-fails)
      printf '\n#[no_mangle]\npub extern \"C\" fn leaked() {}\n' >>"${TMPDIR}/src/kernel/types/screen.rs"
      expect_failure "side effects in types" check_types_no_side_effects
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
