use crate::kernel::core::init::{self, EarlyInitFailure};
use crate::kernel::services::{console, diagnostics};
use crate::kernel::types::KernelRange;

// These come from outside Rust.
// The linker script gives us the kernel and `.bss` boundaries, and the arch startup code gives us
// a few tiny hooks that tests can use to steer or observe boot.
unsafe extern "C" {
    static kernel_start: u8;
    static kernel_end: u8;
    static bss_start: u8;
    static bss_end: u8;

    fn kfs_arch_is_test_mode() -> u32;
    fn kfs_arch_should_fail_bss() -> u32;
    fn kfs_arch_should_fail_layout() -> u32;
    fn kfs_arch_should_fail_string() -> u32;
    fn kfs_arch_should_fail_memory() -> u32;
    fn kfs_arch_force_no_cpuid() -> u32;
    fn kfs_arch_force_disable_simd() -> u32;
    fn kfs_arch_qemu_exit(code: u8) -> !;
    fn kfs_arch_halt_forever() -> !;
}

const QEMU_EXIT_PASS: u8 = 0x10;
const QEMU_EXIT_FAIL: u8 = 0x11;

#[no_mangle]
// `kmain` is where startup assembly hands control to Rust.
//
// Keep this path boring:
// - in tests, say "we made it here",
// - run the early boot checks,
// - then either exit QEMU or drop into the normal console loop.
//
// Each failure maps to one short marker so the test log stays easy to read.
pub extern "C" fn kmain() -> ! {
    if is_test_mode() {
        diagnostics::initialize();
        diagnostics::write_line("KMAIN_OK");
    }

    match init::run_early_init() {
        Ok(()) => {
            if is_test_mode() {
                diagnostics::write_line("EARLY_INIT_OK");
                diagnostics::write_line("KMAIN_FLOW_OK");
                qemu_exit(QEMU_EXIT_PASS);
            }
            console::start_keyboard_echo_loop()
        }
        Err(EarlyInitFailure::BssCanary) => runtime_fail("BSS_FAIL"),
        Err(EarlyInitFailure::Layout) => runtime_fail("LAYOUT_FAIL"),
        Err(EarlyInitFailure::StringHelpers) => runtime_fail("STRING_HELPERS_FAIL"),
        Err(EarlyInitFailure::MemoryHelpers) => runtime_fail("MEMORY_HELPERS_FAIL"),
    }
}

// `init.rs` only needs yes/no answers, so these wrappers hide the raw arch hooks.
pub(crate) fn is_test_mode() -> bool {
    unsafe { kfs_arch_is_test_mode() != 0 }
}

pub(crate) fn bss_canary_is_zero() -> bool {
    unsafe { kfs_arch_should_fail_bss() == 0 }
}

pub(crate) fn layout_override_requested() -> bool {
    unsafe { kfs_arch_should_fail_layout() != 0 }
}

pub(crate) fn string_override_requested() -> bool {
    unsafe { kfs_arch_should_fail_string() != 0 }
}

pub(crate) fn memory_override_requested() -> bool {
    unsafe { kfs_arch_should_fail_memory() != 0 }
}

pub(crate) fn simd_force_no_cpuid_requested() -> bool {
    unsafe { kfs_arch_force_no_cpuid() != 0 }
}

pub(crate) fn simd_force_disable_requested() -> bool {
    unsafe { kfs_arch_force_disable_simd() != 0 }
}

// The linker gives us raw addresses. `KernelRange` makes the later layout checks easier to read.
pub(crate) fn kernel_range() -> KernelRange {
    KernelRange::new(
        core::ptr::addr_of!(kernel_start) as usize,
        core::ptr::addr_of!(kernel_end) as usize,
    )
}

pub(crate) fn bss_range() -> KernelRange {
    KernelRange::new(
        core::ptr::addr_of!(bss_start) as usize,
        core::ptr::addr_of!(bss_end) as usize,
    )
}

// Tests need a clean finish instead of an infinite loop, so we leave QEMU with an explicit code.
pub(crate) fn qemu_exit(code: u8) -> ! {
    unsafe { kfs_arch_qemu_exit(code) }
}

// On a real boot, an unrecoverable early failure just stops here.
pub(crate) fn halt_forever() -> ! {
    unsafe { kfs_arch_halt_forever() }
}

// Shared failure path for early boot.
// In tests we print a marker and exit. In a normal boot we just halt.
pub(crate) fn runtime_fail(marker: &str) -> ! {
    if is_test_mode() {
        diagnostics::write_line(marker);
        qemu_exit(QEMU_EXIT_FAIL);
    }
    halt_forever()
}
