#![no_std]

unsafe extern "C" {
    static kernel_start: u8;
    static kernel_end: u8;
    static bss_start: u8;
    static bss_end: u8;
}

#[no_mangle]
/// This marker reads linker-provided addresses so tests can prove they exist.
///
/// The math here turns raw start/end addresses into sizes for the kernel area
/// and the `.bss` area.
pub extern "C" fn kfs_layout_symbols_marker() -> usize {
    let kernel_lo = core::ptr::addr_of!(kernel_start) as usize;
    let kernel_hi = core::ptr::addr_of!(kernel_end) as usize;
    let bss_lo = core::ptr::addr_of!(bss_start) as usize;
    let bss_hi = core::ptr::addr_of!(bss_end) as usize;
    kernel_hi.wrapping_sub(kernel_lo) + bss_hi.wrapping_sub(bss_lo)
}
