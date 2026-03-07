#![no_std]

#[path = "string/string_impl.rs"]
mod string_impl;

use string_impl::{strcmp, strlen};

#[no_mangle]
/// This marker proves the string helper module was linked into the kernel.
///
/// It calls the helper functions in a tiny, harmless way so the linker keeps
/// the code around for tests.
pub extern "C" fn kfs_string_helpers_marker() -> i32 {
    let empty = [0u8];
    unsafe { (strlen(empty.as_ptr()) as i32) + strcmp(empty.as_ptr(), empty.as_ptr()) }
}
