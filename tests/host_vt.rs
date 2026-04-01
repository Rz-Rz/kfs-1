use kfs::kernel::drivers::vga_text::{
    build_terminal_label_cells, terminal_label, vga_text_blit_viewport, vga_text_cell,
    VgaHistoryCursor, VgaTerminalBank, VGA_TEXT_BLANK_BYTE, VGA_TEXT_DEFAULT_COLOR,
    VGA_TEXT_TERMINAL_COUNT,
};
use kfs::kernel::types::screen::VGA_TEXT_DIMENSIONS;

#[test]
fn terminal_buffers_keep_output_and_cursor_state_isolated() {
    let mut bank = VgaTerminalBank::new();
    bank.reset();

    bank.terminal_mut(0).expect("terminal 0").put_byte(b'A');

    let terminal_one = bank.terminal_mut(1).expect("terminal 1");
    terminal_one.put_byte(b'B');
    terminal_one.put_byte(b'\n');
    terminal_one.put_byte(b'C');

    let first = bank.terminal(0).expect("terminal 0");
    assert_eq!(first.history[0], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'A'));
    assert_eq!(
        first.history[VGA_TEXT_DIMENSIONS.width()],
        vga_text_cell(VGA_TEXT_DEFAULT_COLOR, VGA_TEXT_BLANK_BYTE)
    );
    assert_eq!(first.cursor, VgaHistoryCursor { row: 0, col: 1 });

    let second = bank.terminal(1).expect("terminal 1");
    assert_eq!(second.history[0], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'B'));
    assert_eq!(
        second.history[VGA_TEXT_DIMENSIONS.width()],
        vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'C')
    );
    assert_eq!(second.cursor, VgaHistoryCursor { row: 1, col: 1 });
}

#[test]
fn active_terminal_selection_keeps_each_buffer_intact() {
    let mut bank = VgaTerminalBank::new();
    bank.reset();

    bank.active_mut().put_byte(b'1');
    assert!(bank.create_terminal());
    assert!(bank.create_terminal());
    assert!(bank.set_active(2));
    bank.active_mut().put_byte(b'2');

    let terminal_zero = bank.terminal(0).expect("terminal 0");
    assert_eq!(
        terminal_zero.history[0],
        vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'1')
    );

    let terminal_two = bank.terminal(2).expect("terminal 2");
    assert_eq!(
        terminal_two.history[0],
        vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'2')
    );
    assert_eq!(terminal_two.cursor, VgaHistoryCursor { row: 0, col: 1 });

    assert!(!bank.set_active(VGA_TEXT_TERMINAL_COUNT));
    assert_eq!(bank.active_index, 2);
}

#[test]
// This checks that creating a terminal appends a new Greek label and focuses the new screen.
fn creating_a_terminal_appends_a_new_labeled_screen() {
    let mut bank = VgaTerminalBank::new();
    bank.reset();

    assert_eq!(bank.active_count(), 1);
    assert_eq!(terminal_label(bank.active_label_index()), b"alpha");

    assert!(bank.create_terminal());
    assert_eq!(bank.active_count(), 2);
    assert_eq!(bank.active_index, 1);
    assert_eq!(terminal_label(bank.active_label_index()), b"beta");

    bank.active_mut().put_byte(b'B');
    assert_eq!(
        bank.terminal(bank.active_slot()).expect("active slot").history[0],
        vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'B')
    );
}

#[test]
// This checks that destroying the current terminal focuses a surviving neighbor.
fn destroying_the_current_terminal_removes_it_from_the_active_order() {
    let mut bank = VgaTerminalBank::new();
    bank.reset();
    assert!(bank.create_terminal());
    assert!(bank.create_terminal());

    bank.active_mut().put_byte(b'G');
    assert_eq!(terminal_label(bank.active_label_index()), b"gamma");
    assert_eq!(bank.active_count(), 3);

    assert!(bank.destroy_active_terminal());
    assert_eq!(bank.active_count(), 2);
    assert_eq!(bank.active_index, 1);
    assert_eq!(terminal_label(bank.active_label_index()), b"beta");

    assert!(bank.destroy_active_terminal());
    assert_eq!(bank.active_count(), 1);
    assert_eq!(bank.active_index, 0);
    assert_eq!(terminal_label(bank.active_label_index()), b"alpha");

    assert!(!bank.destroy_active_terminal());
    assert_eq!(bank.active_count(), 1);
}

#[test]
// This checks that switching terminals changes which saved screen contents would be visible.
fn switching_active_terminal_changes_the_visible_view() {
    let mut bank = VgaTerminalBank::new();
    bank.reset();

    bank.terminal_mut(0).expect("terminal 0").put_byte(b'A');
    assert!(bank.create_terminal());
    bank.terminal_mut(1).expect("terminal 1").put_byte(b'B');
    assert!(bank.set_active(0));

    let blank = vga_text_cell(VGA_TEXT_DEFAULT_COLOR, VGA_TEXT_BLANK_BYTE);
    let mut screen = vec![0u16; VGA_TEXT_DIMENSIONS.cell_count()];

    vga_text_blit_viewport(
        &bank.active().history,
        VGA_TEXT_DIMENSIONS.width(),
        VGA_TEXT_DIMENSIONS.height(),
        bank.active().viewport_top,
        &mut screen,
        blank,
    );
    assert_eq!(screen[0], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'A'));

    assert!(bank.set_active(1));
    vga_text_blit_viewport(
        &bank.active().history,
        VGA_TEXT_DIMENSIONS.width(),
        VGA_TEXT_DIMENSIONS.height(),
        bank.active().viewport_top,
        &mut screen,
        blank,
    );
    assert_eq!(screen[0], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'B'));

    assert!(bank.set_active(0));
    vga_text_blit_viewport(
        &bank.active().history,
        VGA_TEXT_DIMENSIONS.width(),
        VGA_TEXT_DIMENSIONS.height(),
        bank.active().viewport_top,
        &mut screen,
        blank,
    );
    assert_eq!(screen[0], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'A'));
}

#[test]
// This checks that the top-right overlay cells show the current Greek terminal name.
fn terminal_label_overlay_is_right_aligned_and_clears_leftover_cells() {
    let alpha = build_terminal_label_cells(0, VGA_TEXT_DEFAULT_COLOR);
    let beta = build_terminal_label_cells(1, VGA_TEXT_DEFAULT_COLOR);
    let blank = vga_text_cell(VGA_TEXT_DEFAULT_COLOR, VGA_TEXT_BLANK_BYTE);

    assert_eq!(alpha[0], blank);
    assert_eq!(alpha[1], blank);
    assert_eq!(alpha[2], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'a'));
    assert_eq!(alpha[6], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'a'));

    assert_eq!(beta[0], blank);
    assert_eq!(beta[1], blank);
    assert_eq!(beta[2], blank);
    assert_eq!(beta[3], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'b'));
    assert_eq!(beta[6], vga_text_cell(VGA_TEXT_DEFAULT_COLOR, b'a'));
}
