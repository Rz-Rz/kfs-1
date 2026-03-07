use super::{vga_text_write_screen, VGA_TEXT_DEFAULT_COLOR};
use crate::kernel::machine::port::Port;
use crate::kernel::types::screen::{CursorPos, VGA_TEXT_DIMENSIONS};

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_TEXT_CELL_COUNT: usize = VGA_TEXT_DIMENSIONS.cell_count();
const VGA_CRTC_ADDR_PORT: Port = Port::new(0x3D4);
const VGA_CRTC_DATA_PORT: Port = Port::new(0x3D5);
const VGA_CURSOR_START_REGISTER: u8 = 0x0A;
const VGA_CURSOR_END_REGISTER: u8 = 0x0B;
const VGA_CURSOR_HIGH_REGISTER: u8 = 0x0E;
const VGA_CURSOR_LOW_REGISTER: u8 = 0x0F;
const VGA_CURSOR_START_SCANLINE: u8 = 0x00;
const VGA_CURSOR_END_SCANLINE: u8 = 0x0F;

static mut VGA_CURSOR: CursorPos = CursorPos::new(0, 0);
static mut VGA_HARDWARE_CURSOR_ENABLED: bool = false;

fn vga_cursor_position(cursor: CursorPos) -> u16 {
    ((cursor.row * VGA_TEXT_DIMENSIONS.width()) + cursor.col) as u16
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

unsafe fn vga_set_hardware_cursor(cursor: CursorPos) {
    let value = vga_cursor_position(cursor);
    unsafe {
        vga_write_cursor_register(VGA_CURSOR_HIGH_REGISTER, ((value >> 8) & 0x00ff) as u8);
        vga_write_cursor_register(VGA_CURSOR_LOW_REGISTER, (value & 0x00ff) as u8);
    }
}

pub(super) fn write_bytes(bytes: &[u8]) {
    unsafe {
        ensure_hardware_cursor_enabled();

        let mut shadow = [0u16; VGA_TEXT_CELL_COUNT];
        for (index, cell) in shadow.iter_mut().enumerate() {
            *cell = core::ptr::read_volatile(VGA_TEXT_BUFFER.add(index));
        }

        VGA_CURSOR = vga_text_write_screen(
            &mut shadow,
            VGA_TEXT_DIMENSIONS,
            VGA_CURSOR,
            VGA_TEXT_DEFAULT_COLOR,
            bytes,
        );

        for (index, cell) in shadow.iter().enumerate() {
            core::ptr::write_volatile(VGA_TEXT_BUFFER.add(index), *cell);
        }

        vga_set_hardware_cursor(VGA_CURSOR);
    }
}
