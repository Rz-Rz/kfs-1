mod writer;

pub const VGA_TEXT_DEFAULT_COLOR: u16 = 0x02;

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

pub(crate) fn write_bytes(bytes: &[u8]) {
    writer::write_bytes(bytes);
}
