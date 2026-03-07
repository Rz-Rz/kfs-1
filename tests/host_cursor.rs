include!("../src/kernel/vga/vga_impl.rs");

#[test]
// This checks that a new cursor begins at the top-left corner of the screen grid.
fn cursor_starts_at_origin() {
    let cursor = VgaCursor::new();
    assert_eq!(cursor.row, 0);
    assert_eq!(cursor.col, 0);
}

#[test]
// This checks that printing one visible byte uses the current cell and then moves one column right.
fn printable_byte_advances_cursor_on_same_row() {
    let mut cursor = VgaCursor::new();
    let result = cursor.put_byte(b'4');
    assert_eq!(result.cell_index, Some(0));
    assert!(!result.scrolled);
    assert_eq!(cursor.row, 0);
    assert_eq!(cursor.col, 1);
}

#[test]
// This checks that a newline changes the cursor position without asking the caller to draw a character.
fn newline_moves_to_next_row_without_writing_a_cell() {
    let mut cursor = VgaCursor::new();
    assert_eq!(cursor.put_byte(b'4').cell_index, Some(0));
    assert_eq!(cursor.put_byte(b'2').cell_index, Some(1));
    let result = cursor.put_byte(b'\n');
    assert_eq!(result.cell_index, None);
    assert!(!result.scrolled);
    assert_eq!(cursor.row, 1);
    assert_eq!(cursor.col, 0);
}

#[test]
// This checks that writing in the last column wraps to the first column of the next row.
fn last_column_wraps_to_next_row() {
    let mut cursor = VgaCursor {
        row: 0,
        col: VGA_WIDTH - 1,
    };
    let result = cursor.put_byte(b'X');
    assert_eq!(result.cell_index, Some(VGA_WIDTH - 1));
    assert!(!result.scrolled);
    assert_eq!(cursor.row, 1);
    assert_eq!(cursor.col, 0);
}
