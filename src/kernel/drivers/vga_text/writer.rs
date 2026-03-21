use super::vga_text_cell;
use crate::kernel::types::screen::VGA_TEXT_DIMENSIONS;

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_COLOR_LIGHT_GREEN_ON_BLACK: u16 = 0x02;

static mut VGA_CURSOR_INDEX: usize = 0;

pub(super) fn reset_cursor() {
    unsafe {
        VGA_CURSOR_INDEX = 0;
    }
}

pub(super) fn write_bytes(bytes: &[u8]) {
    for &byte in bytes {
        write_byte(byte);
    }
}

fn write_byte(byte: u8) {
    unsafe {
        let max_cells = VGA_TEXT_DIMENSIONS.cell_count();
        if VGA_CURSOR_INDEX >= max_cells {
            VGA_CURSOR_INDEX = 0;
        }
        core::ptr::write_volatile(
            VGA_TEXT_BUFFER.add(VGA_CURSOR_INDEX),
            vga_text_cell(VGA_COLOR_LIGHT_GREEN_ON_BLACK, byte),
        );
        VGA_CURSOR_INDEX += 1;
    }
}
