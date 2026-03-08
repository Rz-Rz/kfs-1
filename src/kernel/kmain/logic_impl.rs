pub fn layout_order_is_sane(
    kernel_lo: usize,
    kernel_hi: usize,
    bss_lo: usize,
    bss_hi: usize,
    layout_override: bool,
) -> bool {
    if layout_override {
        return false;
    }

    kernel_hi > kernel_lo && kernel_lo <= bss_lo && bss_lo <= bss_hi && bss_hi <= kernel_hi
}

pub fn vga_text_cell(color: u16, byte: u8) -> u16 {
    (color << 8) | (byte as u16)
}
