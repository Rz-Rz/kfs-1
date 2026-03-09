#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[path = "types.rs"]
mod kernel_types;
#[path = "kmain/logic_impl.rs"]
mod kmain_logic;
use kernel_types::{KernelRange, Port};
use kmain_logic::{layout_order_is_sane, vga_text_cell};

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_COLOR_LIGHT_GREEN_ON_BLACK: u16 = 0x02;
const COM1_DATA: Port = Port::new(0x3f8);
const COM1_INTERRUPT_ENABLE: Port = COM1_DATA.offset(1);
const COM1_FIFO_CONTROL: Port = COM1_DATA.offset(2);
const COM1_LINE_CONTROL: Port = COM1_DATA.offset(3);
const COM1_MODEM_CONTROL: Port = COM1_DATA.offset(4);
const COM1_LINE_STATUS: Port = COM1_DATA.offset(5);
const QEMU_DEBUG_EXIT_PORT: Port = Port::new(0xf4);
const QEMU_EXIT_PASS: u8 = 0x10;
const QEMU_EXIT_FAIL: u8 = 0x11;

#[no_mangle]
pub static mut KFS_M4_BSS_CANARY: u32 = 0;

#[no_mangle]
pub static mut KFS_M4_LAYOUT_OVERRIDE: u32 = 0;

#[no_mangle]
pub static mut KFS_M5_STRING_OVERRIDE: u32 = 0;

#[no_mangle]
pub static mut KFS_M5_MEMORY_OVERRIDE: u32 = 0;

unsafe extern "C" {
    static kernel_start: u8;
    static kernel_end: u8;
    static bss_start: u8;
    static bss_end: u8;
    static kfs_test_mode: u8;
    fn kfs_strlen(ptr: *const u8) -> usize;
    fn kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32;
    fn kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8;
    fn kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8;
}

#[derive(Copy, Clone)]
enum EarlyInitFailure {
    BssCanary,
    Layout,
    StringHelpers,
    MemoryHelpers,
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    if is_test_mode() {
        serial_init();
        serial_write_line("PANIC");
        qemu_exit(QEMU_EXIT_FAIL);
    }
    halt_forever()
}

#[no_mangle]
pub extern "C" fn kmain() -> ! {
    if is_test_mode() {
        serial_init();
        serial_write_line("KMAIN_OK");
    }

    match run_early_init() {
        Ok(()) => {
            if is_test_mode() {
                serial_write_line("EARLY_INIT_OK");
            }
            write_42_to_vga();

            if is_test_mode() {
                serial_write_line("KMAIN_FLOW_OK");
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

fn run_early_init() -> Result<(), EarlyInitFailure> {
    if !bss_canary_is_zero() {
        return Err(EarlyInitFailure::BssCanary);
    }

    if is_test_mode() {
        serial_write_line("BSS_OK");
    }

    if !layout_is_sane() {
        return Err(EarlyInitFailure::Layout);
    }

    if is_test_mode() {
        serial_write_line("LAYOUT_OK");
    }

    if !string_helpers_are_sane() {
        return Err(EarlyInitFailure::StringHelpers);
    }

    if is_test_mode() {
        serial_write_line("STRING_HELPERS_OK");
    }

    if !memory_helpers_are_sane() {
        return Err(EarlyInitFailure::MemoryHelpers);
    }

    if is_test_mode() {
        serial_write_line("MEMORY_HELPERS_OK");
    }

    Ok(())
}

fn bss_canary_is_zero() -> bool {
    unsafe { core::ptr::addr_of!(KFS_M4_BSS_CANARY).read_volatile() == 0 }
}

fn layout_is_sane() -> bool {
    let kernel = KernelRange::new(
        core::ptr::addr_of!(kernel_start) as usize,
        core::ptr::addr_of!(kernel_end) as usize,
    );
    let bss = KernelRange::new(
        core::ptr::addr_of!(bss_start) as usize,
        core::ptr::addr_of!(bss_end) as usize,
    );
    let layout_override =
        unsafe { core::ptr::addr_of!(KFS_M4_LAYOUT_OVERRIDE).read_volatile() != 0 };

    layout_order_is_sane(kernel, bss, layout_override)
}

fn string_helpers_are_sane() -> bool {
    if string_override_requested() {
        return false;
    }

    let empty = [0u8];
    let embedded = [b'o', b'k', 0, b'x', 0];

    if unsafe { kfs_strlen(empty.as_ptr()) } != 0 {
        return false;
    }

    if unsafe { kfs_strlen(embedded.as_ptr()) } != 2 {
        return false;
    }

    if is_test_mode() {
        serial_write_line("STRLEN_OK");
    }

    let equal = *b"42\0";
    let prefix = *b"ab\0";
    let longer = *b"abc\0";
    let high_lhs = [0x80, 0];
    let high_rhs = [0x7f, 0];

    if unsafe { kfs_strcmp(equal.as_ptr(), equal.as_ptr()) } != 0 {
        return false;
    }

    if unsafe { kfs_strcmp(prefix.as_ptr(), longer.as_ptr()) } >= 0 {
        return false;
    }

    if unsafe { kfs_strcmp(high_lhs.as_ptr(), high_rhs.as_ptr()) } <= 0 {
        return false;
    }

    if is_test_mode() {
        serial_write_line("STRCMP_OK");
    }

    true
}

fn string_override_requested() -> bool {
    unsafe { core::ptr::addr_of!(KFS_M5_STRING_OVERRIDE).read_volatile() != 0 }
}

fn memory_helpers_are_sane() -> bool {
    if memory_override_requested() {
        return false;
    }

    let src = [1u8, 2u8, 3u8];
    let mut dst = [0xAAu8, 0xBBu8, 0xCCu8, 0xDDu8, 0xEEu8];
    let copy_dst = unsafe { dst.as_mut_ptr().add(1) };
    let copy_return = unsafe { kfs_memcpy(copy_dst, src.as_ptr(), src.len()) };

    if copy_return != copy_dst {
        return false;
    }

    if dst != [0xAAu8, 1u8, 2u8, 3u8, 0xEEu8] {
        return false;
    }

    if is_test_mode() {
        serial_write_line("MEMCPY_OK");
    }

    let mut fill = [0x11u8, 0x22u8, 0x33u8, 0x44u8, 0x55u8];
    let fill_dst = unsafe { fill.as_mut_ptr().add(1) };
    let fill_return = unsafe { kfs_memset(fill_dst, 0x99u8, 3) };

    if fill_return != fill_dst {
        return false;
    }

    if fill != [0x11u8, 0x99u8, 0x99u8, 0x99u8, 0x55u8] {
        return false;
    }

    if is_test_mode() {
        serial_write_line("MEMSET_OK");
    }

    true
}

fn memory_override_requested() -> bool {
    unsafe { core::ptr::addr_of!(KFS_M5_MEMORY_OVERRIDE).read_volatile() != 0 }
}

fn write_42_to_vga() {
    unsafe {
        core::ptr::write_volatile(
            VGA_TEXT_BUFFER,
            vga_text_cell(VGA_COLOR_LIGHT_GREEN_ON_BLACK, b'4'),
        );
        core::ptr::write_volatile(
            VGA_TEXT_BUFFER.add(1),
            vga_text_cell(VGA_COLOR_LIGHT_GREEN_ON_BLACK, b'2'),
        );
    }
}

fn runtime_fail(marker: &str) -> ! {
    if is_test_mode() {
        serial_write_line(marker);
        qemu_exit(QEMU_EXIT_FAIL);
    }
    halt_forever()
}

fn is_test_mode() -> bool {
    unsafe { core::ptr::addr_of!(kfs_test_mode).read_volatile() != 0 }
}

fn serial_init() {
    unsafe {
        outb(COM1_INTERRUPT_ENABLE, 0x00);
        outb(COM1_LINE_CONTROL, 0x80);
        outb(COM1_DATA, 0x03);
        outb(COM1_INTERRUPT_ENABLE, 0x00);
        outb(COM1_LINE_CONTROL, 0x03);
        outb(COM1_FIFO_CONTROL, 0xc7);
        outb(COM1_MODEM_CONTROL, 0x03);
    }
}

fn serial_write_line(message: &str) {
    serial_write(message);
    serial_write("\n");
}

fn serial_write(message: &str) {
    for byte in message.bytes() {
        serial_write_byte(byte);
    }
}

fn serial_write_byte(byte: u8) {
    while unsafe { inb(COM1_LINE_STATUS) & 0x20 } == 0 {}
    unsafe {
        outb(COM1_DATA, byte);
    }
}

fn qemu_exit(code: u8) -> ! {
    unsafe {
        outb(QEMU_DEBUG_EXIT_PORT, code);
    }
    halt_forever()
}

unsafe fn outb(port: Port, value: u8) {
    core::arch::asm!(
        "out dx, al",
        in("dx") port.as_u16(),
        in("al") value,
        options(nomem, nostack, preserves_flags)
    );
}

unsafe fn inb(port: Port) -> u8 {
    let value: u8;
    core::arch::asm!(
        "in al, dx",
        in("dx") port.as_u16(),
        out("al") value,
        options(nomem, nostack, preserves_flags)
    );
    value
}

#[inline(always)]
fn halt_forever() -> ! {
    loop {
        unsafe {
            core::arch::asm!("cli", "hlt", options(nomem, nostack));
        }
    }
}
