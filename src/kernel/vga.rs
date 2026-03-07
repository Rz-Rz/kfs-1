#![no_std]

#[path = "vga/vga_impl.rs"]
mod vga_impl;

use vga_impl::VgaCursor;

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_COLOR_LIGHT_GREEN_ON_BLACK: u16 = 0x02;

static mut VGA_CURSOR: VgaCursor = VgaCursor::new();

#[inline(always)]
/// This writes one colored character directly into VGA text memory.
///
/// The screen is just a block of memory where each cell stores a color byte
/// and a character byte together.
unsafe fn vga_write_cell(cell_index: usize, byte: u8) {
    let value = (VGA_COLOR_LIGHT_GREEN_ON_BLACK << 8) | (byte as u16);
    unsafe { core::ptr::write_volatile(VGA_TEXT_BUFFER.add(cell_index), value) };
}

#[no_mangle]
/// This resets the saved cursor back to the top-left corner of the screen.
///
/// Think of it like moving a text editor cursor back to row 0, column 0.
pub extern "C" fn vga_init() {
    unsafe {
        VGA_CURSOR = VgaCursor::new();
    }
}

#[no_mangle]
/// This prints one byte and then moves the cursor to the next place.
///
/// Normal bytes become visible characters. A newline byte moves the cursor to
/// the next row without drawing a symbol.
pub extern "C" fn vga_putc(byte: u8) {
    unsafe {
        let mut cursor = VGA_CURSOR;
        if let Some(cell_index) = cursor.put_byte(byte) {
            vga_write_cell(cell_index, byte);
        }
        VGA_CURSOR = cursor;
    }
}

#[no_mangle]
/// This walks through a zero-terminated byte string and prints it one byte at a time.
///
/// The ending `0` byte is a marker that means "stop here"; it is not printed.
pub extern "C" fn vga_puts(text: *const u8) {
    let mut offset: usize = 0;
    loop {
        let byte = unsafe { core::ptr::read(text.add(offset)) };
        if byte == 0 {
            return;
        }
        vga_putc(byte);
        offset += 1;
    }
}

#[no_mangle]
/// This tiny marker proves the VGA module was linked into the final kernel.
///
/// The return value itself is not important for users; tests just need a
/// callable symbol that touches this module.
pub extern "C" fn kfs_vga_writer_marker() -> u16 {
    let demo = *b"VGA\0";
    vga_init();
    vga_puts(demo.as_ptr());
    VGA_COLOR_LIGHT_GREEN_ON_BLACK
}
