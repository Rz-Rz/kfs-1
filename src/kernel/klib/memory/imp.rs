#[inline(never)]
pub(super) unsafe fn memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    let mut idx: usize = 0;
    while idx < len {
        let value = unsafe { src.add(idx).read() };
        unsafe { dst.add(idx).write(value) };
        idx += 1;
    }
    dst
}

#[inline(never)]
pub(super) unsafe fn memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    let mut idx: usize = 0;
    while idx < len {
        unsafe { dst.add(idx).write(value) };
        idx += 1;
    }
    dst
}
