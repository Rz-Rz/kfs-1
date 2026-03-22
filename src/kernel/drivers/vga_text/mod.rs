mod writer;

use crate::kernel::types::screen::{CursorPos, ScreenDimensions};

pub const VGA_TEXT_DEFAULT_COLOR: u16 = 0x02;
const VGA_TEXT_BLANK_BYTE: u8 = b' ';

pub fn vga_text_cell(color: u16, byte: u8) -> u16 {
    (color << 8) | (byte as u16)
}

pub fn vga_text_normalize_cursor(cursor: usize, cell_count: usize) -> usize {
    if cell_count == 0 || cursor >= cell_count {
        return 0;
    }

    cursor
}

pub fn vga_text_write_cells(buffer: &mut [u16], cursor: usize, color: u16, bytes: &[u8]) -> usize {
    if buffer.is_empty() {
        return 0;
    }

    let mut cursor = vga_text_normalize_cursor(cursor, buffer.len());

    for &byte in bytes {
        buffer[cursor] = vga_text_cell(color, byte);
        cursor += 1;
        if cursor >= buffer.len() {
            cursor = 0;
        }
    }

    cursor
}

pub fn vga_text_normalize_cursor_pos(cursor: CursorPos, dimensions: ScreenDimensions) -> CursorPos {
    if dimensions.width() == 0 || dimensions.height() == 0 {
        return CursorPos::new(0, 0);
    }

    let row = if cursor.row >= dimensions.height() {
        dimensions.height() - 1
    } else {
        cursor.row
    };
    let col = if cursor.col >= dimensions.width() {
        dimensions.width() - 1
    } else {
        cursor.col
    };

    CursorPos::new(row, col)
}

pub fn vga_text_write_screen(
    buffer: &mut [u16],
    dimensions: ScreenDimensions,
    cursor: CursorPos,
    color: u16,
    bytes: &[u8],
) -> CursorPos {
    if buffer.is_empty() || dimensions.width() == 0 || dimensions.height() == 0 {
        return CursorPos::new(0, 0);
    }

    if buffer.len() < dimensions.cell_count() {
        return CursorPos::new(0, 0);
    }

    let blank = vga_text_cell(color, VGA_TEXT_BLANK_BYTE);
    let mut cursor = vga_text_normalize_cursor_pos(cursor, dimensions);

    for &byte in bytes {
        if byte == b'\n' {
            cursor = vga_text_advance_line(buffer, dimensions, cursor, blank);
            continue;
        }

        let index = vga_text_cursor_index(dimensions, cursor);
        unsafe {
            *buffer.get_unchecked_mut(index) = vga_text_cell(color, byte);
        }

        let next_col = cursor.col + 1;
        if next_col >= dimensions.width() {
            cursor = vga_text_advance_line(buffer, dimensions, cursor, blank);
            continue;
        }

        cursor = CursorPos::new(cursor.row, next_col);
    }

    cursor
}

fn vga_text_cursor_index(dimensions: ScreenDimensions, cursor: CursorPos) -> usize {
    (cursor.row * dimensions.width()) + cursor.col
}

fn vga_text_advance_line(
    buffer: &mut [u16],
    dimensions: ScreenDimensions,
    cursor: CursorPos,
    blank: u16,
) -> CursorPos {
    let next_row = cursor.row + 1;
    if next_row < dimensions.height() {
        return CursorPos::new(next_row, 0);
    }

    vga_text_scroll_up(buffer, dimensions, blank);
    CursorPos::new(dimensions.height() - 1, 0)
}

fn vga_text_scroll_up(buffer: &mut [u16], dimensions: ScreenDimensions, blank: u16) {
    let width = dimensions.width();
    let height = dimensions.height();

    for row in 1..height {
        let dst_start = (row - 1) * width;
        let src_start = row * width;
        for col in 0..width {
            unsafe {
                let value = *buffer.get_unchecked(src_start + col);
                *buffer.get_unchecked_mut(dst_start + col) = value;
            }
        }
    }

    let last_row_start = (height - 1) * width;
    for col in 0..width {
        unsafe {
            *buffer.get_unchecked_mut(last_row_start + col) = blank;
        }
    }
}

pub(crate) fn write_bytes(bytes: &[u8]) {
    writer::write_bytes(bytes);
}
