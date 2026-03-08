#[allow(dead_code)]
#[path = "../src/kernel/types.rs"]
mod kernel_types;
#[path = "../src/kernel/kmain/logic_impl.rs"]
mod kmain_logic;

use kernel_types::KernelRange;
use kmain_logic::{layout_order_is_sane, vga_text_cell};

#[test]
fn layout_order_accepts_non_empty_monotonic_bounds() {
    assert!(layout_order_is_sane(
        KernelRange::new(0x1000, 0x1800),
        KernelRange::new(0x1400, 0x1500),
        false,
    ));
}

#[test]
fn layout_order_rejects_empty_kernel_span() {
    assert!(!layout_order_is_sane(
        KernelRange::new(0x1000, 0x1000),
        KernelRange::new(0x1000, 0x1000),
        false,
    ));
}

#[test]
fn layout_order_rejects_kernel_start_after_bss_start() {
    assert!(!layout_order_is_sane(
        KernelRange::new(0x2000, 0x2800),
        KernelRange::new(0x1800, 0x1900),
        false,
    ));
}

#[test]
fn layout_order_rejects_bss_start_after_bss_end() {
    assert!(!layout_order_is_sane(
        KernelRange::new(0x1000, 0x2800),
        KernelRange::new(0x2200, 0x2100),
        false,
    ));
}

#[test]
fn layout_order_rejects_bss_end_after_kernel_end() {
    assert!(!layout_order_is_sane(
        KernelRange::new(0x1000, 0x1800),
        KernelRange::new(0x1400, 0x1900),
        false,
    ));
}

#[test]
fn layout_order_rejects_override_flag() {
    assert!(!layout_order_is_sane(
        KernelRange::new(0x1000, 0x1800),
        KernelRange::new(0x1400, 0x1500),
        true,
    ));
}

#[test]
fn vga_text_cell_encodes_color_and_ascii_byte() {
    assert_eq!(vga_text_cell(0x02, b'4'), 0x0234);
}

#[test]
fn vga_text_cell_preserves_low_byte_for_character() {
    assert_eq!(vga_text_cell(0x0f, b'Z') & 0x00ff, b'Z' as u16);
}
