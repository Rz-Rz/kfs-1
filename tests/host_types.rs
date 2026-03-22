use kfs::kernel::machine::port::Port;
use kfs::kernel::types::range::KernelRange;

#[test]
fn port_new_preserves_wrapped_value() {
    assert_eq!(Port::new(0x3f8).as_u16(), 0x3f8);
}

#[test]
fn port_offset_advances_register_address() {
    assert_eq!(Port::new(0x3f8).offset(5).as_u16(), 0x3fd);
}

#[test]
fn port_offset_wraps_on_u16_overflow() {
    assert_eq!(Port::new(0xfffe).offset(3).as_u16(), 1);
}

#[test]
fn kernel_range_len_tracks_non_empty_span() {
    assert_eq!(KernelRange::new(0x1000, 0x1800).len(), 0x800);
}

#[test]
fn kernel_range_preserves_start_and_end_bounds() {
    let range = KernelRange::new(0x1000, 0x1800);

    assert_eq!(range.start(), 0x1000);
    assert_eq!(range.end(), 0x1800);
}

#[test]
fn kernel_range_is_empty_when_end_is_not_after_start() {
    assert!(KernelRange::new(0x1000, 0x1000).is_empty());
    assert!(KernelRange::new(0x1800, 0x1000).is_empty());
}

#[test]
fn kernel_range_contains_uses_half_open_bounds() {
    let range = KernelRange::new(0x1000, 0x1800);

    assert!(range.contains(0x1000));
    assert!(range.contains(0x17ff));
    assert!(!range.contains(0x1800));
}

#[test]
fn kernel_range_len_saturates_when_end_precedes_start() {
    assert_eq!(KernelRange::new(0x1800, 0x1000).len(), 0);
}
