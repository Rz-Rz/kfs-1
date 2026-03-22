mod imp;

#[no_mangle]
pub unsafe extern "C" fn kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    unsafe { memcpy(dst, src, len) }
}

#[no_mangle]
pub unsafe extern "C" fn kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    unsafe { memset(dst, value, len) }
}

pub unsafe fn memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    unsafe { imp::memcpy(dst, src, len) }
}

pub unsafe fn memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    unsafe { imp::memset(dst, value, len) }
}
