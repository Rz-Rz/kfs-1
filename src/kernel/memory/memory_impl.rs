/// This copies `len` bytes from one memory area into another.
///
/// Safety: the caller must make sure both memory ranges are valid for `len`
/// bytes. This simple version copies forward one byte at a time.
pub unsafe fn memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    let mut idx: usize = 0;
    while idx < len {
        let value = unsafe { core::ptr::read_volatile(src.add(idx)) };
        unsafe { core::ptr::write_volatile(dst.add(idx), value) };
        idx += 1;
    }
    dst
}

/// This writes the same byte value into `len` bytes of memory.
///
/// Safety: the caller must make sure the destination range is valid for the
/// full write.
pub unsafe fn memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    let mut idx: usize = 0;
    while idx < len {
        unsafe { core::ptr::write_volatile(dst.add(idx), value) };
        idx += 1;
    }
    dst
}
