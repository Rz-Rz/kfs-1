use super::{
    build_terminal_label_cells, render_logical_screen_to_physical, screen_render_origin,
    vga_text_blit_viewport, vga_text_cell, VgaTerminalBank, VGA_TEXT_BLANK_BYTE,
    VGA_TEXT_TERMINAL_LABEL_WIDTH,
};
use crate::kernel::machine::port::Port;
use crate::kernel::types::screen::{ColorCode, VGA_TEXT_DIMENSIONS, VGA_TEXT_PHYSICAL_DIMENSIONS};

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_TEXT_LOGICAL_CELL_COUNT: usize = VGA_TEXT_DIMENSIONS.cell_count();
const VGA_TEXT_PHYSICAL_CELL_COUNT: usize = VGA_TEXT_PHYSICAL_DIMENSIONS.cell_count();
const VGA_CRTC_ADDR_PORT: Port = Port::new(0x3D4);
const VGA_CRTC_DATA_PORT: Port = Port::new(0x3D5);
const VGA_CURSOR_START_REGISTER: u8 = 0x0A;
const VGA_CURSOR_END_REGISTER: u8 = 0x0B;
const VGA_CURSOR_HIGH_REGISTER: u8 = 0x0E;
const VGA_CURSOR_LOW_REGISTER: u8 = 0x0F;
const VGA_CURSOR_START_SCANLINE: u8 = 0x00;
const VGA_CURSOR_END_SCANLINE: u8 = 0x0F;

static mut VGA_TERMINALS: VgaTerminalBank = VgaTerminalBank::new();
// The freestanding kernel stack is small, so redraw scratch buffers cannot live on the stack.
static mut VGA_LOGICAL_SHADOW: [u16; VGA_TEXT_LOGICAL_CELL_COUNT] =
    [0; VGA_TEXT_LOGICAL_CELL_COUNT];
static mut VGA_PHYSICAL_SHADOW: [u16; VGA_TEXT_PHYSICAL_CELL_COUNT] =
    [0; VGA_TEXT_PHYSICAL_CELL_COUNT];
static mut VGA_HARDWARE_CURSOR_ENABLED: bool = false;
static mut VGA_LOGICAL_STATE_INITIALIZED: bool = false;
static mut VGA_STATE_INITIALIZED: bool = false;

fn vga_cursor_position(row: usize, col: usize) -> u16 {
    ((row * VGA_TEXT_PHYSICAL_DIMENSIONS.width()) + col) as u16
}

unsafe fn vga_write_cursor_register(register: u8, value: u8) {
    unsafe {
        VGA_CRTC_ADDR_PORT.write_u8(register);
        VGA_CRTC_DATA_PORT.write_u8(value);
    }
}

unsafe fn vga_enable_hardware_cursor() {
    unsafe {
        vga_write_cursor_register(VGA_CURSOR_START_REGISTER, VGA_CURSOR_START_SCANLINE);
        vga_write_cursor_register(VGA_CURSOR_END_REGISTER, VGA_CURSOR_END_SCANLINE);
        VGA_HARDWARE_CURSOR_ENABLED = true;
    }
}

unsafe fn ensure_hardware_cursor_enabled() {
    unsafe {
        if !VGA_HARDWARE_CURSOR_ENABLED {
            vga_enable_hardware_cursor();
        }
    }
}

unsafe fn vga_set_hardware_cursor(row: usize, col: usize) {
    let value = vga_cursor_position(row, col);
    unsafe {
        vga_write_cursor_register(VGA_CURSOR_HIGH_REGISTER, ((value >> 8) & 0x00ff) as u8);
        vga_write_cursor_register(VGA_CURSOR_LOW_REGISTER, (value & 0x00ff) as u8);
    }
}

unsafe fn redraw_active_terminal() {
    let bank = unsafe { &*core::ptr::addr_of!(VGA_TERMINALS) };
    let terminal = bank.active();
    let blank = vga_text_cell(terminal.color, VGA_TEXT_BLANK_BYTE);
    let logical = unsafe { &mut *core::ptr::addr_of_mut!(VGA_LOGICAL_SHADOW) };
    let shadow = unsafe { &mut *core::ptr::addr_of_mut!(VGA_PHYSICAL_SHADOW) };

    // First render the active terminal into its logical viewport, then center that viewport into
    // the fixed 80x25 VGA buffer that the hardware actually exposes.
    vga_text_blit_viewport(
        &terminal.history,
        VGA_TEXT_DIMENSIONS.width(),
        VGA_TEXT_DIMENSIONS.height(),
        terminal.viewport_top,
        logical,
        blank,
    );

    render_logical_screen_to_physical(
        VGA_TEXT_DIMENSIONS,
        VGA_TEXT_PHYSICAL_DIMENSIONS,
        logical,
        shadow,
        blank,
    );

    let label = build_terminal_label_cells(bank.active_label_index(), terminal.color);
    let label_start = VGA_TEXT_PHYSICAL_DIMENSIONS
        .width()
        .saturating_sub(VGA_TEXT_TERMINAL_LABEL_WIDTH);
    let mut offset = 0;
    while offset < VGA_TEXT_TERMINAL_LABEL_WIDTH {
        unsafe {
            *shadow.get_unchecked_mut(label_start + offset) = *label.get_unchecked(offset);
        }
        offset += 1;
    }

    for (index, cell) in shadow.iter().enumerate() {
        unsafe {
            core::ptr::write_volatile(VGA_TEXT_BUFFER.add(index), *cell);
        }
    }

    let cursor_row = terminal
        .cursor
        .row
        .saturating_sub(terminal.viewport_top)
        .min(VGA_TEXT_DIMENSIONS.height() - 1);
    let origin = screen_render_origin(VGA_TEXT_DIMENSIONS, VGA_TEXT_PHYSICAL_DIMENSIONS);
    unsafe {
        vga_set_hardware_cursor(
            origin.row() + cursor_row,
            origin.col() + terminal.cursor.col,
        );
    }
}

unsafe fn initialize_logical_state() {
    unsafe {
        (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS)).reset();
        VGA_LOGICAL_STATE_INITIALIZED = true;
    }
}

unsafe fn ensure_logical_state_initialized() {
    unsafe {
        if !VGA_LOGICAL_STATE_INITIALIZED {
            initialize_logical_state();
        }
    }
}

unsafe fn initialize_state() {
    unsafe {
        ensure_logical_state_initialized();
        ensure_hardware_cursor_enabled();
        redraw_active_terminal();
        VGA_STATE_INITIALIZED = true;
    }
}

unsafe fn ensure_state_initialized() {
    unsafe {
        ensure_logical_state_initialized();
        if !VGA_STATE_INITIALIZED {
            initialize_state();
            return;
        }

        ensure_hardware_cursor_enabled();
    }
}

pub(super) fn write_bytes(bytes: &[u8]) {
    unsafe {
        ensure_state_initialized();
        (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS))
            .active_mut()
            .put_bytes(bytes);
        redraw_active_terminal();
    }
}

pub(super) fn backspace() {
    unsafe {
        ensure_state_initialized();
        (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS))
            .active_mut()
            .backspace();
        redraw_active_terminal();
    }
}

pub(super) fn viewport_up() {
    unsafe {
        ensure_state_initialized();
        (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS))
            .active_mut()
            .viewport_up();
        redraw_active_terminal();
    }
}

pub(super) fn viewport_down() {
    unsafe {
        ensure_state_initialized();
        (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS))
            .active_mut()
            .viewport_down();
        redraw_active_terminal();
    }
}

pub(super) fn set_cursor(row: usize, col: usize) {
    unsafe {
        ensure_state_initialized();
        (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS))
            .active_mut()
            .move_cursor(row, col);
        redraw_active_terminal();
    }
}

pub(super) fn set_active_terminal(index: usize) -> bool {
    unsafe {
        ensure_state_initialized();
        let changed = (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS)).set_active(index);
        if changed {
            redraw_active_terminal();
        }
        changed
    }
}

pub(super) fn create_terminal() -> bool {
    unsafe {
        ensure_state_initialized();
        let created = (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS)).create_terminal();
        if created {
            redraw_active_terminal();
        }
        created
    }
}

pub(super) fn destroy_active_terminal() -> bool {
    unsafe {
        ensure_state_initialized();
        let destroyed = (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS)).destroy_active_terminal();
        if destroyed {
            redraw_active_terminal();
        }
        destroyed
    }
}

pub(super) fn set_color(color: ColorCode) {
    unsafe {
        ensure_logical_state_initialized();
        (&mut *core::ptr::addr_of_mut!(VGA_TERMINALS))
            .active_mut()
            .color = color;
        if VGA_STATE_INITIALIZED {
            redraw_active_terminal();
        }
    }
}

pub(super) fn color() -> ColorCode {
    unsafe {
        ensure_logical_state_initialized();
        (&*core::ptr::addr_of!(VGA_TERMINALS)).active().color
    }
}
