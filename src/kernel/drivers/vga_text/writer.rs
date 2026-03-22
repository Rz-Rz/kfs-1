use super::{vga_text_write_screen, VGA_TEXT_DEFAULT_COLOR};
use crate::kernel::types::screen::{CursorPos, VGA_TEXT_DIMENSIONS};

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_TEXT_CELL_COUNT: usize = VGA_TEXT_DIMENSIONS.cell_count();

static mut VGA_CURSOR: CursorPos = CursorPos::new(0, 0);

pub(super) fn write_bytes(bytes: &[u8]) {
    unsafe {
        let mut shadow = [0u16; VGA_TEXT_CELL_COUNT];
        for (index, cell) in shadow.iter_mut().enumerate() {
            *cell = core::ptr::read_volatile(VGA_TEXT_BUFFER.add(index));
        }

        VGA_CURSOR = vga_text_write_screen(
            &mut shadow,
            VGA_TEXT_DIMENSIONS,
            VGA_CURSOR,
            VGA_TEXT_DEFAULT_COLOR,
            bytes,
        );

        for (index, cell) in shadow.iter().enumerate() {
            core::ptr::write_volatile(VGA_TEXT_BUFFER.add(index), *cell);
        }
    }
}
