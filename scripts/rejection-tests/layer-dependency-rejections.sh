#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
core-imports-machine-fails
services-import-driver-leaf-fails
drivers-own-boot-policy-fails
klib-depends-on-device-code-fails
types-depend-on-policy-fails
machine-depends-on-drivers-fails
EOF
}

describe_case() {
  case "$1" in
    core-imports-machine-fails) printf '%s\n' "rejects core depending on machine/arch internals" ;;
    services-import-driver-leaf-fails) printf '%s\n' "rejects services importing driver leaves or touching raw hw I/O" ;;
    drivers-own-boot-policy-fails) printf '%s\n' "rejects drivers owning boot policy or importing core/services" ;;
    klib-depends-on-device-code-fails) printf '%s\n' "rejects klib depending on non-types layers or policy code" ;;
    types-depend-on-policy-fails) printf '%s\n' "rejects types owning I/O or orchestration policy" ;;
    machine-depends-on-drivers-fails) printf '%s\n' "rejects machine depending on higher-layer modules" ;;
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

make_tree() {
  TMPDIR="$(mktemp -d)"
  mkdir -p "${TMPDIR}/src/kernel"/{core,services,drivers/vga_text,klib/string,klib/memory,types,machine}
  cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
use crate::kernel::services::console::console_write;
pub fn kmain() { console_write(); }
EOF
  cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
pub fn init() {}
EOF
  cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn console_write() {}
EOF
  cat >"${TMPDIR}/src/kernel/drivers/vga_text/mod.rs" <<'EOF'
pub fn console_putc() {}
EOF
  cat >"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs" <<'EOF'
pub fn write_cell() {}
EOF
  cat >"${TMPDIR}/src/kernel/klib/string/mod.rs" <<'EOF'
pub fn len(_ptr: *const u8) -> usize { 0 }
EOF
  cat >"${TMPDIR}/src/kernel/klib/memory/mod.rs" <<'EOF'
pub fn copy(_src: *const u8, _dst: *mut u8, _n: usize) {}
EOF
  cat >"${TMPDIR}/src/kernel/types/screen.rs" <<'EOF'
#[repr(transparent)]
pub struct ColorCode(pub u8);
EOF
  cat >"${TMPDIR}/src/kernel/machine/port.rs" <<'EOF'
#[repr(transparent)]
pub struct Port(pub u16);
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

check_core_forbidden_layer_imports() {
  ! rg -n '(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\b(crate::kernel::|super::|crate::)?(drivers|machine|arch)::' -S "${TMPDIR}/src/kernel/core"
}

check_services_driver_leaf_or_raw_hw() {
  ! rg -n '(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\bcrate::kernel::drivers::[A-Za-z0-9_]+::(writer|imp|_impl|logic_impl|memory_impl|string_impl)\b|#\[path[[:space:]]*=[[:space:]]*"[^"]*(writer|imp|_impl|logic_impl|memory_impl|string_impl)\.rs"\]|\b(0x[bB]8000|write_volatile|read_volatile|\b(inb|outb)\(|core::arch::asm!)\b' -S "${TMPDIR}/src/kernel/services"
}

check_drivers_boot_policy() {
  ! rg -n '(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\b(crate::kernel::)?(core|services)::|\bfn[[:space:]]+(kmain|run_early_init|serial_init|halt_forever|qemu_exit|panic_init|panic_startup|boot_loop)[[:space:]]*\(|#[[:space:]]*\[panic_handler\]' -S "${TMPDIR}/src/kernel/drivers"
}

check_klib_device_or_policy() {
  ! rg -n '(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\bcrate::kernel::(drivers|services|core|machine|types)::|\b(vga_|\bPort\b|\b(inb|outb)\(|0x[bB]8000|write_volatile|read_volatile|core::arch::asm!)\b' -S "${TMPDIR}/src/kernel/klib"
}

check_types_io_or_policy() {
  ! rg -n '(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\bcrate::kernel::(core|services|drivers|klib)::|\b(inb|outb)\(|0x[bB]8000|write_volatile|read_volatile|core::arch::asm!|\bfn[[:space:]]+(kmain|run_early_init|serial_init|halt_forever|qemu_exit|panic_init|boot_init)[[:space:]]*\(' -S "${TMPDIR}/src/kernel/types"
}

check_machine_upward_or_policy() {
  ! rg -n '(^|[[:space:]])(use|pub[[:space:]]+use)[[:space:]]+[^;\n]*\bcrate::kernel::(core|services|drivers|types|klib)::|\bfn[[:space:]]+(kmain|run_early_init|serial_init|halt_forever|qemu_exit)[[:space:]]*\(|#[[:space:]]*\[panic_handler\]' -S "${TMPDIR}/src/kernel/machine"
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_tree

  case "${CASE}" in
    core-imports-machine-fails)
      printf '\nuse crate::kernel::machine::port::Port;\n' >>"${TMPDIR}/src/kernel/core/entry.rs"
      expect_failure "core importing machine layer" check_core_forbidden_layer_imports
      ;;
    services-import-driver-leaf-fails)
      printf '\n#[path = "../drivers/vga_text/writer.rs"]\nmod writer;\n' >>"${TMPDIR}/src/kernel/services/console.rs"
      printf '\nfn _raw_hw() { let _ = 0xb8000; }\n' >>"${TMPDIR}/src/kernel/services/console.rs"
      expect_failure "services importing driver leaf or using raw hw io" check_services_driver_leaf_or_raw_hw
      ;;
    drivers-own-boot-policy-fails)
      printf '\nuse crate::kernel::core::init;\n\npub fn run_early_init() {}\n' >>"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs"
      expect_failure "drivers owning boot policy" check_drivers_boot_policy
      ;;
    klib-depends-on-device-code-fails)
      printf '\nuse crate::kernel::drivers::vga_text::writer::write_cell;\n' >>"${TMPDIR}/src/kernel/klib/string/mod.rs"
      expect_failure "klib depending on device code" check_klib_device_or_policy
      ;;
    types-depend-on-policy-fails)
      printf '\nuse crate::kernel::core::init;\n' >>"${TMPDIR}/src/kernel/types/screen.rs"
      printf '\nfn kmain() {}\n' >>"${TMPDIR}/src/kernel/types/screen.rs"
      expect_failure "types depending on policy or I/O" check_types_io_or_policy
      ;;
    machine-depends-on-drivers-fails)
      printf '\nuse crate::kernel::drivers::vga_text::mod as drivers_vga_text;\n' >>"${TMPDIR}/src/kernel/machine/port.rs"
      expect_failure "machine depending on drivers/core/services/types/klib" check_machine_upward_or_policy
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
