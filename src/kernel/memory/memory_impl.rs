pub unsafe fn memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    let mut idx: usize = 0;
    while idx < len {
        let value = unsafe { core::ptr::read_volatile(src.add(idx)) };
        unsafe { core::ptr::write_volatile(dst.add(idx), value) };
        idx += 1;
    }
    dst
}

pub unsafe fn memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    let mut idx: usize = 0;
    while idx < len {
        unsafe { core::ptr::write_volatile(dst.add(idx), value) };
        idx += 1;
    }
    dst
}

