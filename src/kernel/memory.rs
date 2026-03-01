#![no_std]
#![no_builtins]

#[path = "memory/memory_impl.rs"]
mod memory_impl;

use memory_impl::{memory_copy_impl, memory_set_impl};

#[no_mangle]
pub unsafe extern "C" fn kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    unsafe { memory_copy(dst, src, len) }
}

#[no_mangle]
pub unsafe extern "C" fn kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    unsafe { memory_set(dst, value, len) }
}

pub unsafe fn memory_copy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    let copy_impl: unsafe fn(*mut u8, *const u8, usize) -> *mut u8 = memory_copy_impl;
    unsafe { copy_impl(dst, src, len) }
}

pub unsafe fn memory_set(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    let set_impl: unsafe fn(*mut u8, u8, usize) -> *mut u8 = memory_set_impl;
    unsafe { set_impl(dst, value, len) }
}
