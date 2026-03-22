mod imp;

#[no_mangle]
pub unsafe extern "C" fn kfs_strlen(ptr: *const u8) -> usize {
    unsafe { strlen(ptr) }
}

#[no_mangle]
pub unsafe extern "C" fn kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32 {
    unsafe { strcmp(lhs, rhs) }
}

pub unsafe fn strlen(ptr: *const u8) -> usize {
    unsafe { imp::strlen(ptr) }
}

pub unsafe fn strcmp(lhs: *const u8, rhs: *const u8) -> i32 {
    unsafe { imp::strcmp(lhs, rhs) }
}
