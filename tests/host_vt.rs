use kfs::kernel::drivers::vga_text::{
    vga_text_cell, VgaHistoryCursor, VgaTerminalBank, VGA_TEXT_BLANK_BYTE,
    VGA_TEXT_DEFAULT_COLOR, VGA_TEXT_TERMINAL_COUNT,
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
