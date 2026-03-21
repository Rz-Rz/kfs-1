use kfs::kernel::drivers::vga_text::{
    vga_text_blit_viewport, vga_text_cell, vga_text_tail_viewport_top, vga_text_write_screen,
    VgaTerminal, VGA_TEXT_BLANK_BYTE, VGA_TEXT_DEFAULT_COLOR, VGA_TEXT_HISTORY_ROWS,
};
use kfs::kernel::types::screen::{CursorPos, ScreenDimensions, VGA_TEXT_DIMENSIONS};

fn idx(dimensions: ScreenDimensions, row: usize, col: usize) -> usize {
    row * dimensions.width() + col
}

#[test]
fn vga_text_write_screen_scrolls_bottom_row_on_newline() {
    let dimensions = ScreenDimensions::new(4, 2);
    let mut buffer = [0u16; 8];

    for col in 0..dimensions.width() {
        buffer[idx(dimensions, 0, col)] = vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'M');
        buffer[idx(dimensions, 1, col)] = vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'K');
    }

    let next = vga_text_write_screen(
        &mut buffer,
        dimensions,
        CursorPos::new(1, 1),
        VGA_TEXT_DEFAULT_COLOR,
        b"\n",
    );

    assert_eq!(next, CursorPos::new(1, 0));
    for col in 0..dimensions.width() {
        assert_eq!(buffer[idx(dimensions, 0, col)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'K'));
        assert_eq!(buffer[idx(dimensions, 1, col)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b' '));
    }
}

#[test]
fn vga_text_write_screen_keeps_latest_rows_visible_after_multiple_scrolls() {
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
    for col in 0..3 {
        assert_eq!(buffer[idx(dimensions, 0, col)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'D' + col as u8));
        assert_eq!(buffer[idx(dimensions, 1, col)], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'G' + col as u8));
    }
}

#[test]
fn vga_text_tail_viewport_top_follows_live_cursor_row() {
    assert_eq!(vga_text_tail_viewport_top(0), 0);
    assert_eq!(vga_text_tail_viewport_top(VGA_TEXT_DIMENSIONS.height() - 1), 0);
    assert_eq!(vga_text_tail_viewport_top(VGA_TEXT_DIMENSIONS.height()), 1);
}

#[test]
fn vga_text_blit_viewport_restores_older_history_rows() {
    let row_width = VGA_TEXT_DIMENSIONS.width();
    let viewport_height = VGA_TEXT_DIMENSIONS.height();
    let mut history = vec![b'.'; VGA_TEXT_HISTORY_ROWS * row_width];

    for row in 0..VGA_TEXT_HISTORY_ROWS {
        let fill = b'A' + ((row % 26) as u8);
        for col in 0..row_width {
            history[(row * row_width) + col] = fill;
        }
    }

    let mut screen = vec![b'?'; row_width * viewport_height];
    vga_text_blit_viewport(&history, row_width, viewport_height, 12, &mut screen, b' ');

    for col in 0..row_width {
        assert_eq!(screen[col], b'M');
        assert_eq!(screen[((viewport_height - 1) * row_width) + col], b'K');
    }
}

#[test]
fn terminal_tracks_tail_viewport_after_history_scroll() {
    let mut terminal = VgaTerminal::new();
    terminal.reset();

    for row in 0..=VGA_TEXT_DIMENSIONS.height() {
        terminal.put_byte(b'A' + (row as u8 % 26));
        terminal.put_byte(b'\n');
    }

    assert_eq!(terminal.viewport_top, 2);
    terminal.viewport_up();
    assert_eq!(terminal.viewport_top, 1);
    terminal.viewport_down();
    assert_eq!(terminal.viewport_top, 2);
}

#[test]
fn terminal_backspace_blanks_the_previous_character_cell() {
    let mut terminal = VgaTerminal::new();
    terminal.reset();
    terminal.put_byte(b'X');
    terminal.put_byte(b'Y');
    terminal.backspace();

    assert_eq!(
        terminal.history[0],
        vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'X')
    );
    assert_eq!(
        terminal.history[1],
        vga_text_cell(VGA_TEXT_DEFAULT_COLOR, VGA_TEXT_BLANK_BYTE)
    );
}
