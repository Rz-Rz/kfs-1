#![no_std]
#![no_builtins]

#[path = "string/string_impl.rs"]
mod string_impl;

use string_impl::{string_cmp_impl, string_len_impl};

#[no_mangle]
pub unsafe extern "C" fn kfs_strlen(ptr: *const u8) -> usize {
    unsafe { string_len(ptr) }
}

#[no_mangle]
pub unsafe extern "C" fn kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32 {
    unsafe { string_cmp(lhs, rhs) }
}

pub unsafe fn string_len(ptr: *const u8) -> usize {
    let len_impl: unsafe fn(*const u8) -> usize = string_len_impl;
    unsafe { len_impl(ptr) }
}

pub unsafe fn string_cmp(lhs: *const u8, rhs: *const u8) -> i32 {
    let cmp_impl: unsafe fn(*const u8, *const u8) -> i32 = string_cmp_impl;
    unsafe { cmp_impl(lhs, rhs) }
}
