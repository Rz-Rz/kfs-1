#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TMPDIR=""

list_cases() {
  cat <<'EOF'
boot-calls-driver-directly-fails
entry-skips-core-init-fails
kmain-calls-vga-directly-fails
core-init-skips-services-fails
services-console-skips-driver-facade-fails
EOF
}

describe_case() {
  case "$1" in
    boot-calls-driver-directly-fails) printf '%s\n' "rejects boot handoff jumping into driver ABI directly" ;;
    entry-skips-core-init-fails) printf '%s\n' "rejects entries that do not reach core init sequencing" ;;
    kmain-calls-vga-directly-fails) printf '%s\n' "rejects kmain calling VGA ABI directly" ;;
    core-init-skips-services-fails) printf '%s\n' "rejects core init skipping services console layer" ;;
    services-console-skips-driver-facade-fails) printf '%s\n' "rejects services console bypassing driver facade" ;;
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

make_runtime_tree() {
  TMPDIR="$(mktemp -d)"
  mkdir -p \
    "${TMPDIR}/src/arch/i386" \
    "${TMPDIR}/src/kernel/core" \
    "${TMPDIR}/src/kernel/services" \
    "${TMPDIR}/src/kernel/drivers/vga_text"

  cat >"${TMPDIR}/src/arch/i386/boot.asm" <<'EOF'
global start
extern kmain

section .text
bits 32
start:
    call kmain
EOF

cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
pub fn init() {
    run_early_init();
}

#[no_mangle]
pub extern "C" fn kmain() -> ! {
    init();
    loop {}
}

fn run_early_init() {}
EOF

  cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
use crate::kernel::services::console;

pub fn init() {
    console::write_banner();
}
EOF

  cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
use crate::kernel::drivers::vga_text;

pub fn write_banner() {
    vga_text::paint();
}

pub fn write(message: *const u8) {}
EOF

  cat >"${TMPDIR}/src/kernel/drivers/vga_text/mod.rs" <<'EOF'
pub fn paint() {
    crate::kernel::drivers::vga_text::writer::write();
}

pub use self::writer::write;
EOF

  cat >"${TMPDIR}/src/kernel/drivers/vga_text/writer.rs" <<'EOF'
pub fn write() {}
EOF
}

check_boot_only_kmain() {
  local boot="${TMPDIR}/src/arch/i386/boot.asm"

  if ! rg -n '^\s*call\s+kmain\b' "${boot}" >/dev/null; then
    return 1
  fi
  if rg -n '^\s*call\s+(?!kmain\b)[A-Za-z_][A-Za-z0-9_]*' -P "${boot}" >/dev/null; then
    return 1
  fi
  return 0
}

check_entry_has_init_chain() {
  local entry="${TMPDIR}/src/kernel/core/entry.rs"

  if ! rg -n '\bfn[[:space:]]+kmain\b' "${entry}" >/dev/null; then
    return 1
  fi
  if ! rg -n '\b(init|run_early_init)\s*\(' "${entry}" >/dev/null; then
    return 1
  fi
  return 0
}

check_entry_no_vga_driver_abi() {
  local entry="${TMPDIR}/src/kernel/core/entry.rs"

  if rg -n '\bvga_[A-Za-z_][A-Za-z0-9_]*\b' "${entry}" >/dev/null; then
    return 1
  fi
  return 0
}

check_init_calls_services() {
  local init="${TMPDIR}/src/kernel/core/init.rs"

  if ! rg -n '\bservices::console\b' "${init}" >/dev/null; then
    return 1
  fi
  if rg -n '\bdrivers::vga_text\b' "${init}" >/dev/null; then
    return 1
  fi
  return 0
}

check_services_to_driver_facade() {
  local console="${TMPDIR}/src/kernel/services/console.rs"

  if ! rg -n '\bdrivers::vga_text\b' "${console}" >/dev/null; then
    return 1
  fi
  return 0
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

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  make_runtime_tree

  case "${CASE}" in
    boot-calls-driver-directly-fails)
      printf '\nextern vga_init\ncall vga_init\n' >>"${TMPDIR}/src/arch/i386/boot.asm"
      expect_failure "direct boot jump into VGA helper" check_boot_only_kmain
      ;;
    entry-skips-core-init-fails)
      cat >"${TMPDIR}/src/kernel/core/entry.rs" <<'EOF'
#[no_mangle]
pub extern "C" fn kmain() -> ! {
    loop {}
}
EOF
      expect_failure "entry without init-chain" check_entry_has_init_chain
      ;;
    kmain-calls-vga-directly-fails)
      printf '\nunsafe fn bad_console() { vga_puts(core::ptr::null()); }\n' >>"${TMPDIR}/src/kernel/core/entry.rs"
      expect_failure "direct vga driver ABI in core entry" check_entry_no_vga_driver_abi
      ;;
    core-init-skips-services-fails)
      cat >"${TMPDIR}/src/kernel/core/init.rs" <<'EOF'
use crate::kernel::drivers::vga_text::writer;

pub fn init() {
    writer::write();
}
EOF
      expect_failure "core init bypassing services console" check_init_calls_services
      ;;
    services-console-skips-driver-facade-fails)
      cat >"${TMPDIR}/src/kernel/services/console.rs" <<'EOF'
pub fn write_banner() {
    unsafe { vga_puts(core::ptr::null()); }
}
EOF
      expect_failure "services console bypassing driver facade" check_services_to_driver_facade
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
