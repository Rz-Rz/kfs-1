include!("../src/kernel/vga/vga_impl.rs");

fn render_terminal(
    terminal: &VgaTerminal,
    visible_geometry: ScreenGeometry,
    history_geometry: ScreenGeometry,
) -> Vec<u16> {
    let blank = vga_text_cell(VGA_BLANK_BYTE, terminal.attribute);
    let mut screen = vec![blank; visible_geometry.cell_count()];
    blit_viewport(
        visible_geometry,
        &terminal.history[..history_geometry.cell_count()],
        terminal.viewport_top,
        &mut screen,
        blank,
    );
    screen
}

#[test]
// This checks that wrap, newline, and backspace all obey the same geometry rules on two screen sizes.
fn writer_wraps_newlines_and_backspaces_under_default_and_alternate_geometries() {
    for visible_geometry in [VGA_GEOMETRY, ScreenGeometry::new(4, 3)] {
        let history_geometry = ScreenGeometry::new(visible_geometry.width, visible_geometry.height + 2);
        let mut terminal = VgaTerminal::new();
        terminal.reset_with_geometry(history_geometry);

        let mut written: usize = 0;
        while written < visible_geometry.width {
            terminal.put_byte_with_geometry(visible_geometry, history_geometry, b'A');
            written += 1;
        }
        assert_eq!(terminal.cursor.row, 1);
        assert_eq!(terminal.cursor.col, 0);

        terminal.put_byte_with_geometry(visible_geometry, history_geometry, b'\n');
        assert_eq!(terminal.cursor.row, 2.min(history_geometry.last_row()));
        assert_eq!(terminal.cursor.col, 0);

        terminal.put_byte_with_geometry(visible_geometry, history_geometry, b'B');
        terminal.backspace_with_geometry(visible_geometry, history_geometry);
        assert_eq!(terminal.cursor.col, 0);
        assert_eq!(
            terminal.history[history_geometry.cell_index(terminal.cursor.row, 0)],
            vga_text_cell(VGA_BLANK_BYTE, VGA_DEFAULT_ATTRIBUTE)
        );
    }
}

#[test]
// This checks that resetting a terminal clears the active history region on both geometries.
fn terminal_reset_clears_the_active_history_for_default_and_alternate_geometries() {
    for visible_geometry in [VGA_GEOMETRY, ScreenGeometry::new(4, 3)] {
        let history_geometry = ScreenGeometry::new(visible_geometry.width, visible_geometry.height + 2);
        let blank = vga_text_cell(VGA_BLANK_BYTE, VGA_DEFAULT_ATTRIBUTE);
        let mut terminal = VgaTerminal::new();

        terminal.put_byte_with_geometry(visible_geometry, history_geometry, b'X');
        terminal.put_byte_with_geometry(visible_geometry, history_geometry, b'Y');
        terminal.reset_with_geometry(history_geometry);

        let screen = render_terminal(&terminal, visible_geometry, history_geometry);
        assert!(screen.iter().all(|cell| *cell == blank));
        assert_eq!(terminal.cursor, VgaHistoryCursor::new());
        assert_eq!(terminal.viewport_top, 0);
    }
}

#[test]
// This checks that scrolling and viewport restores use the same geometry rules on two screen sizes.
fn scroll_and_restore_follow_the_same_geometry_rules_for_two_geometries() {
    for visible_geometry in [VGA_GEOMETRY, ScreenGeometry::new(4, 3)] {
        let history_geometry = ScreenGeometry::new(visible_geometry.width, visible_geometry.height + 2);
        let mut terminal = VgaTerminal::new();
        terminal.reset_with_geometry(history_geometry);

        let mut row: usize = 0;
        while row < visible_geometry.height + 1 {
            terminal.put_byte_with_geometry(
                visible_geometry,
                history_geometry,
                b'A' + (row as u8),
            );
            if row + 1 < visible_geometry.height + 1 {
                terminal.put_byte_with_geometry(visible_geometry, history_geometry, b'\n');
            }
            row += 1;
        }

        let screen = render_terminal(&terminal, visible_geometry, history_geometry);
        assert_eq!(screen[0], vga_text_cell(b'B', VGA_DEFAULT_ATTRIBUTE));
        assert_eq!(
            screen[visible_geometry.cell_index(visible_geometry.last_row(), 0)],
            vga_text_cell(b'A' + (visible_geometry.height as u8), VGA_DEFAULT_ATTRIBUTE)
        );
        assert_eq!(terminal.viewport_top, 1);
    }
}
