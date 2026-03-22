use super::{vga_text_cell, vga_text_normalize_cursor, VGA_TEXT_DEFAULT_COLOR};
use crate::kernel::types::screen::VGA_TEXT_DIMENSIONS;

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;

static mut VGA_CURSOR_INDEX: usize = 0;

pub(super) fn write_bytes(bytes: &[u8]) {
    for &byte in bytes {
        write_byte(byte);
    }
}

fn write_byte(byte: u8) {
    unsafe {
        let max_cells = VGA_TEXT_DIMENSIONS.cell_count();
        VGA_CURSOR_INDEX = vga_text_normalize_cursor(VGA_CURSOR_INDEX, max_cells);
        core::ptr::write_volatile(
            VGA_TEXT_BUFFER.add(VGA_CURSOR_INDEX),
            vga_text_cell(VGA_TEXT_DEFAULT_COLOR, byte),
        );
        VGA_CURSOR_INDEX += 1;
        if VGA_CURSOR_INDEX >= max_cells {
            VGA_CURSOR_INDEX = 0;
        }
    }
}
