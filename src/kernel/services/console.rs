use crate::kernel::drivers::vga_text;

pub(crate) fn write_bytes(bytes: &[u8]) {
    vga_text::init();
    vga_text::write_bytes(bytes);
}
