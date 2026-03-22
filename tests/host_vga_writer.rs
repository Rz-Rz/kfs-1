use kfs::kernel::drivers::vga_text::{
    vga_text_cell, vga_text_write_cells, VGA_TEXT_DEFAULT_COLOR,
};

#[test]
fn vga_writer_writes_bytes_in_sequence() {
    let mut buffer = [0u16; 4];
    let next = vga_text_write_cells(&mut buffer, 0, VGA_TEXT_DEFAULT_COLOR, b"42");

    assert_eq!(buffer[0], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'4'));
    assert_eq!(buffer[1], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'2'));
    assert_eq!(next, 2);
}

#[test]
fn vga_writer_preserves_unwritten_cells() {
    let sentinel = vga_text_cell(0x0f, b'X');
    let mut buffer = [sentinel; 5];

    vga_text_write_cells(&mut buffer, 1, VGA_TEXT_DEFAULT_COLOR, b"42");

    assert_eq!(buffer[0], sentinel);
    assert_eq!(buffer[3], sentinel);
    assert_eq!(buffer[4], sentinel);
}

#[test]
fn vga_writer_wraps_at_buffer_end() {
    let mut buffer = [0u16; 3];
    let next = vga_text_write_cells(&mut buffer, 2, VGA_TEXT_DEFAULT_COLOR, b"42");

    assert_eq!(buffer[2], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'4'));
    assert_eq!(buffer[0], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'2'));
    assert_eq!(next, 1);
}

#[test]
fn vga_writer_continues_from_existing_cursor() {
    let mut buffer = [0u16; 5];
    let next = vga_text_write_cells(&mut buffer, 2, VGA_TEXT_DEFAULT_COLOR, b"42");

    assert_eq!(buffer[2], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'4'));
    assert_eq!(buffer[3], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'2'));
    assert_eq!(next, 4);
}

#[test]
fn vga_writer_handles_empty_buffer() {
    let mut buffer = [];
    let next = vga_text_write_cells(&mut buffer, 7, VGA_TEXT_DEFAULT_COLOR, b"42");

    assert_eq!(next, 0);
}
