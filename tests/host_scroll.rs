include!("../src/kernel/vga/vga_impl.rs");

#[test]
// This checks that a newline on the last row requests a scroll instead of wrapping to row 0.
fn newline_on_last_row_requests_scroll() {
    let mut cursor = VgaCursor {
        row: VGA_HEIGHT - 1,
        col: 12,
    };

    let result = cursor.put_byte(b'\n');

    assert_eq!(result.cell_index, None);
    assert!(result.scrolled);
    assert_eq!(cursor.row, VGA_HEIGHT - 1);
    assert_eq!(cursor.col, 0);
}

#[test]
// This checks that writing into the bottom-right cell requests a scroll after the write.
fn last_cell_write_requests_scroll() {
    let mut cursor = VgaCursor {
        row: VGA_HEIGHT - 1,
        col: VGA_WIDTH - 1,
    };

    let result = cursor.put_byte(b'X');

    assert_eq!(result.cell_index, Some(VGA_CELLS - 1));
    assert!(result.scrolled);
    assert_eq!(cursor.row, VGA_HEIGHT - 1);
    assert_eq!(cursor.col, 0);
}

#[test]
// This checks that scrolling shifts every row up and clears the last row.
fn scroll_buffer_moves_rows_up_and_blanks_last_row() {
    let mut buffer = [b'.'; VGA_CELLS];
    let mut row: usize = 0;

    while row < VGA_HEIGHT {
        let mut col: usize = 0;
        while col < VGA_WIDTH {
            buffer[(row * VGA_WIDTH) + col] = b'A' + (row as u8);
            col += 1;
        }
        row += 1;
    }

    scroll_buffer(&mut buffer, b' ');

    let mut check_row: usize = 0;
    while check_row + 1 < VGA_HEIGHT {
        let expected = b'A' + ((check_row + 1) as u8);
        let mut col: usize = 0;
        while col < VGA_WIDTH {
            assert_eq!(buffer[(check_row * VGA_WIDTH) + col], expected);
            col += 1;
        }
        check_row += 1;
    }

    let last_row_start = (VGA_HEIGHT - 1) * VGA_WIDTH;
    let mut col: usize = 0;
    while col < VGA_WIDTH {
        assert_eq!(buffer[last_row_start + col], b' ');
        col += 1;
    }
}
