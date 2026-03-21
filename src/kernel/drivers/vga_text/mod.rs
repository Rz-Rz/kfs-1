mod writer;

pub fn vga_text_cell(color: u16, byte: u8) -> u16 {
    (color << 8) | (byte as u16)
}

pub(crate) fn init() {
    writer::reset_cursor();
}

pub(crate) fn write_bytes(bytes: &[u8]) {
    writer::write_bytes(bytes);
}
