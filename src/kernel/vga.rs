#![no_std]

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_WIDTH: usize = 80;
const VGA_HEIGHT: usize = 25;
const VGA_COLOR_LIGHT_GREEN_ON_BLACK: u16 = 0x02;

static mut VGA_CURSOR_INDEX: usize = 0;

#[inline(always)]
unsafe fn vga_write_cell(cell_index: usize, byte: u8) {
    let value = (VGA_COLOR_LIGHT_GREEN_ON_BLACK << 8) | (byte as u16);
    unsafe { core::ptr::write_volatile(VGA_TEXT_BUFFER.add(cell_index), value) };
}

#[no_mangle]
pub extern "C" fn vga_init() {
    unsafe {
        VGA_CURSOR_INDEX = 0;
    }
}

#[no_mangle]
pub extern "C" fn vga_putc(byte: u8) {
    unsafe {
        let max_cells = VGA_WIDTH * VGA_HEIGHT;
        if VGA_CURSOR_INDEX >= max_cells {
            VGA_CURSOR_INDEX = 0;
        }
        vga_write_cell(VGA_CURSOR_INDEX, byte);
        VGA_CURSOR_INDEX += 1;
    }
}

#[no_mangle]
pub extern "C" fn vga_puts(text: *const u8) {
    let mut offset: usize = 0;
    loop {
        let byte = unsafe { core::ptr::read(text.add(offset)) };
        if byte == 0 {
            return;
        }
        vga_putc(byte);
        offset += 1;
    }
}

#[no_mangle]
pub extern "C" fn kfs_vga_writer_marker() -> u16 {
    let demo = *b"VGA\0";
    vga_init();
    vga_puts(demo.as_ptr());
    VGA_COLOR_LIGHT_GREEN_ON_BLACK
}
