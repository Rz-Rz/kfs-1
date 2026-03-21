use kfs::kernel::drivers::vga_text::{
    vga_text_cell, vga_text_normalize_cursor, vga_text_normalize_cursor_pos,
    vga_text_write_screen, VGA_TEXT_DEFAULT_COLOR,
};
use kfs::kernel::types::screen::{CursorPos, ScreenDimensions, VGA_TEXT_DIMENSIONS};

fn idx(dimensions: ScreenDimensions, row: usize, col: usize) -> usize {
    row * dimensions.width() + col
}

#[test]
fn vga_text_normalize_cursor_resets_out_of_bounds_cursor_to_zero() {
    assert_eq!(
        vga_text_normalize_cursor(VGA_TEXT_DIMENSIONS.cell_count(), VGA_TEXT_DIMENSIONS.cell_count()),
        0
    );
}

#[test]
fn vga_text_normalize_cursor_pos_clamps_out_of_bounds_positions() {
    assert_eq!(
        vga_text_normalize_cursor_pos(
            CursorPos::new(VGA_TEXT_DIMENSIONS.height() + 9, VGA_TEXT_DIMENSIONS.width() + 11),
            VGA_TEXT_DIMENSIONS,
        ),
        CursorPos::new(VGA_TEXT_DIMENSIONS.height() - 1, VGA_TEXT_DIMENSIONS.width() - 1)
    );
}

#[test]
fn vga_text_write_screen_advances_cursor_on_same_row() {
    let dimensions = ScreenDimensions::new(3, 2);
    let mut buffer = [0u16; 6];

    let next = vga_text_write_screen(
        &mut buffer,
        dimensions,
        CursorPos::new(0, 0),
        VGA_TEXT_DEFAULT_COLOR,
        b"4",
    );

    assert_eq!(next, CursorPos::new(0, 1));
    assert_eq!(buffer[idx(dimensions, 0, 0)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'4'));
}

#[test]
fn vga_text_write_screen_moves_to_next_row_for_newline() {
    let dimensions = ScreenDimensions::new(3, 2);
    let mut buffer = [0xdead; 6];

    let next = vga_text_write_screen(
        &mut buffer,
        dimensions,
        CursorPos::new(0, 0),
        VGA_TEXT_DEFAULT_COLOR,
        b"42\n",
    );

    assert_eq!(next, CursorPos::new(1, 0));
    assert_eq!(buffer[idx(dimensions, 0, 0)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'4'));
    assert_eq!(buffer[idx(dimensions, 0, 1)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'2'));
    assert_eq!(buffer[idx(dimensions, 0, 2)], 0xdead);
}

#[test]
fn vga_text_write_screen_wraps_last_column_to_next_row() {
    let dimensions = ScreenDimensions::new(3, 2);
    let mut buffer = [0u16; 6];

    let next = vga_text_write_screen(
        &mut buffer,
        dimensions,
        CursorPos::new(0, dimensions.width() - 1),
        VGA_TEXT_DEFAULT_COLOR,
        b"X",
    );

    assert_eq!(next, CursorPos::new(1, 0));
    assert_eq!(
        buffer[idx(dimensions, 0, dimensions.width() - 1)],
        vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'X')
    );
}
