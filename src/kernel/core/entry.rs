use crate::kernel::core::init::{self, EarlyInitFailure};
use crate::kernel::services::diagnostics;
use crate::kernel::types::KernelRange;

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
    fn kfs_arch_qemu_exit(code: u8) -> !;
    fn kfs_arch_halt_forever() -> !;
}

const QEMU_EXIT_PASS: u8 = 0x10;
const QEMU_EXIT_FAIL: u8 = 0x11;

#[no_mangle]
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
            halt_forever()
        }
        Err(EarlyInitFailure::BssCanary) => runtime_fail("BSS_FAIL"),
        Err(EarlyInitFailure::Layout) => runtime_fail("LAYOUT_FAIL"),
        Err(EarlyInitFailure::StringHelpers) => runtime_fail("STRING_HELPERS_FAIL"),
        Err(EarlyInitFailure::MemoryHelpers) => runtime_fail("MEMORY_HELPERS_FAIL"),
    }
}

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

pub(crate) fn qemu_exit(code: u8) -> ! {
    unsafe { kfs_arch_qemu_exit(code) }
}

pub(crate) fn halt_forever() -> ! {
    unsafe { kfs_arch_halt_forever() }
}

pub(crate) fn runtime_fail(marker: &str) -> ! {
    if is_test_mode() {
        diagnostics::write_line(marker);
        qemu_exit(QEMU_EXIT_FAIL);
    }
    halt_forever()
}
