#![no_std]

#[path = "vga/vga_format_impl.rs"]
mod vga_format_impl;
#[path = "vga/vga_impl.rs"]
mod vga_impl;
#[path = "vga/vga_palette.rs"]
mod vga_palette;

use vga_format_impl::{format_usize_decimal, render_printf_with_args, MAX_USIZE_DECIMAL_DIGITS};
use vga_impl::{scroll_buffer, vga_attribute, VgaCursor, VGA_CELLS, VGA_DEFAULT_ATTRIBUTE, VGA_WIDTH};
pub use vga_palette::VgaColor;

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_BLANK_BYTE: u8 = b' ';
const VGA_CRTC_ADDR_PORT: u16 = 0x3D4;
const VGA_CRTC_DATA_PORT: u16 = 0x3D5;
const VGA_CURSOR_START_REGISTER: u8 = 0x0A;
const VGA_CURSOR_END_REGISTER: u8 = 0x0B;
const VGA_CURSOR_HIGH_REGISTER: u8 = 0x0E;
const VGA_CURSOR_LOW_REGISTER: u8 = 0x0F;
const VGA_CURSOR_START_SCANLINE: u8 = 0x00;
const VGA_CURSOR_END_SCANLINE: u8 = 0x0F;

static mut VGA_CURSOR: VgaCursor = VgaCursor::new();
static mut VGA_ATTRIBUTE: u8 = VGA_DEFAULT_ATTRIBUTE;

#[inline(always)]
const fn vga_cell_value(byte: u8, attribute: u8) -> u16 {
    ((attribute as u16) << 8) | (byte as u16)
}

#[inline(always)]
/// This writes one colored character directly into VGA text memory.
///
/// The screen is just a block of memory where each cell stores a color byte
/// and a character byte together.
unsafe fn vga_write_cell(cell_index: usize, byte: u8, attribute: u8) {
    unsafe {
        core::ptr::write_volatile(VGA_TEXT_BUFFER.add(cell_index), vga_cell_value(byte, attribute))
    };
}

#[inline(always)]
/// This shifts all screen rows up by one and clears the last visible line.
unsafe fn vga_scroll_up(attribute: u8) {
    let buffer = unsafe { core::slice::from_raw_parts_mut(VGA_TEXT_BUFFER, VGA_CELLS) };
    scroll_buffer(buffer, vga_cell_value(VGA_BLANK_BYTE, attribute));
}

#[inline(always)]
/// This writes one byte to an x86 I/O port.
unsafe fn port_write_u8(port: u16, value: u8) {
    unsafe {
        core::arch::asm!(
            "out dx, al",
            in("dx") port,
            in("al") value,
            options(nomem, nostack, preserves_flags)
        );
    }
}

#[inline(always)]
/// This converts the software cursor row/col into one hardware cursor cell index.
fn vga_cursor_position(cursor: VgaCursor) -> usize {
    (cursor.row * VGA_WIDTH) + cursor.col
}

#[inline(always)]
/// This programs the VGA hardware cursor registers (ports 0x3D4/0x3D5).
unsafe fn vga_set_hardware_cursor(position: usize) {
    let value = position as u16;
    unsafe {
        port_write_u8(VGA_CRTC_ADDR_PORT, VGA_CURSOR_HIGH_REGISTER);
        port_write_u8(VGA_CRTC_DATA_PORT, ((value >> 8) & 0x00ff) as u8);
        port_write_u8(VGA_CRTC_ADDR_PORT, VGA_CURSOR_LOW_REGISTER);
        port_write_u8(VGA_CRTC_DATA_PORT, (value & 0x00ff) as u8);
    }
}

#[inline(always)]
/// This forces the hardware text cursor to be visible with a simple full-height block.
unsafe fn vga_enable_hardware_cursor() {
    unsafe {
        port_write_u8(VGA_CRTC_ADDR_PORT, VGA_CURSOR_START_REGISTER);
        port_write_u8(VGA_CRTC_DATA_PORT, VGA_CURSOR_START_SCANLINE);
        port_write_u8(VGA_CRTC_ADDR_PORT, VGA_CURSOR_END_REGISTER);
        port_write_u8(VGA_CRTC_DATA_PORT, VGA_CURSOR_END_SCANLINE);
    }
}

#[no_mangle]
/// This resets the saved cursor back to the top-left corner of the screen.
///
/// Think of it like moving a text editor cursor back to row 0, column 0.
pub extern "C" fn vga_init() {
    unsafe {
        VGA_CURSOR = VgaCursor::new();
        VGA_ATTRIBUTE = VGA_DEFAULT_ATTRIBUTE;
        vga_enable_hardware_cursor();
        let cursor = VGA_CURSOR;
        vga_set_hardware_cursor(vga_cursor_position(cursor));
    }
}

#[no_mangle]
/// This sets the active VGA text colors used by subsequent writes.
///
/// Both values use the low 4 bits of the VGA palette encoding.
pub extern "C" fn vga_set_color(foreground: u8, background: u8) {
    unsafe {
        VGA_ATTRIBUTE = vga_attribute(foreground, background);
    }
}

#[no_mangle]
/// This returns the currently active VGA attribute byte.
pub extern "C" fn vga_get_color() -> u8 {
    unsafe { VGA_ATTRIBUTE }
}

#[no_mangle]
/// This prints one byte and then moves the cursor to the next place.
///
/// Normal bytes become visible characters. A newline byte moves the cursor to
/// the next row without drawing a symbol.
pub extern "C" fn vga_putc(byte: u8) {
    unsafe {
        let mut cursor = VGA_CURSOR;
        let attribute = VGA_ATTRIBUTE;
        let result = cursor.put_byte(byte);
        if let Some(cell_index) = result.cell_index {
            vga_write_cell(cell_index, byte, attribute);
        }
        if result.scrolled {
            vga_scroll_up(attribute);
        }
        VGA_CURSOR = cursor;
        vga_set_hardware_cursor(vga_cursor_position(cursor));
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
/// This prints one unsigned integer in decimal.
pub extern "C" fn vga_putusize(value: usize) {
    let mut digits_uninit = core::mem::MaybeUninit::<[u8; MAX_USIZE_DECIMAL_DIGITS]>::uninit();
    let digits = unsafe { &mut *digits_uninit.as_mut_ptr() };
    let rendered = format_usize_decimal(value, digits);
    let mut idx: usize = 0;
    while idx < rendered.len() {
        let digit = unsafe { core::ptr::read(rendered.as_ptr().add(idx)) };
        vga_putc(digit);
        idx += 1;
    }
}

#[no_mangle]
/// This renders a tiny `printf` subset with one argument.
pub extern "C" fn vga_printf(format: *const u8, value: usize) {
    vga_printf_args(format, &value as *const usize, 1);
}

#[no_mangle]
/// This renders a tiny `printf` subset with an explicit argument list.
///
/// Supported specifiers are documented in `render_printf_with_args`.
pub extern "C" fn vga_printf_args(format: *const u8, args: *const usize, arg_count: usize) {
    render_printf_with_args(format, args, arg_count, |byte| vga_putc(byte));
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
    VGA_DEFAULT_ATTRIBUTE as u16
}
