use kfs::kernel::drivers::vga_text::{
    vga_text_cell, vga_text_normalize_cursor_pos, vga_text_write_screen, VGA_TEXT_DEFAULT_COLOR,
};
use kfs::kernel::types::screen::{CursorPos, ScreenDimensions, VGA_TEXT_DIMENSIONS};

fn idx(dimensions: ScreenDimensions, row: usize, col: usize) -> usize {
    row * dimensions.width() + col
}

#[test]
fn vga_bonus_normalize_cursor_pos_clamps_out_of_bounds_to_last_visible_cell() {
    assert_eq!(
        vga_text_normalize_cursor_pos(
            CursorPos::new(VGA_TEXT_DIMENSIONS.height(), VGA_TEXT_DIMENSIONS.width()),
            VGA_TEXT_DIMENSIONS,
        ),
        CursorPos::new(VGA_TEXT_DIMENSIONS.height() - 1, VGA_TEXT_DIMENSIONS.width() - 1)
    );
}

#[test]
fn vga_bonus_write_screen_advances_cursor_over_newline() {
    let dimensions = ScreenDimensions::new(4, 3);
    let mut buffer = [0u16; 12];

    let next = vga_text_write_screen(
        &mut buffer,
        dimensions,
        CursorPos::new(0, 0),
        VGA_TEXT_DEFAULT_COLOR,
        b"ab\nc",
    );

    assert_eq!(next, CursorPos::new(1, 1));
    assert_eq!(buffer[idx(dimensions, 0, 0)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'a'));
    assert_eq!(buffer[idx(dimensions, 0, 1)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'b'));
    assert_eq!(buffer[idx(dimensions, 1, 0)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'c'));
}

#[test]
fn vga_bonus_write_screen_scrolls_latest_rows_into_view() {
    let dimensions = ScreenDimensions::new(4, 2);
    let mut buffer = [0u16; 8];

    let next = vga_text_write_screen(
        &mut buffer,
        dimensions,
        CursorPos::new(0, 0),
        VGA_TEXT_DEFAULT_COLOR,
        b"ABC\nDEF\nGHI",
    );

    assert_eq!(next, CursorPos::new(1, 3));
    assert_eq!(buffer[idx(dimensions, 0, 0)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'D'));
    assert_eq!(buffer[idx(dimensions, 0, 1)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'E'));
    assert_eq!(buffer[idx(dimensions, 0, 2)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'F'));
    assert_eq!(buffer[idx(dimensions, 1, 0)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'G'));
    assert_eq!(buffer[idx(dimensions, 1, 1)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'H'));
    assert_eq!(buffer[idx(dimensions, 1, 2)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'I'));
}
