use super::kernel_types::KernelRange;

pub fn layout_order_is_sane(
    kernel: KernelRange,
    bss: KernelRange,
    layout_override: bool,
) -> bool {
    if layout_override {
        return false;
    }

    let kernel_lo = kernel.start();
    let kernel_hi = kernel.end();
    let bss_lo = bss.start();
    let bss_hi = bss.end();

    !kernel.is_empty() && kernel_lo <= bss_lo && bss_lo <= bss_hi && bss_hi <= kernel_hi
}

pub fn vga_text_cell(color: u16, byte: u8) -> u16 {
    (color << 8) | (byte as u16)
}
