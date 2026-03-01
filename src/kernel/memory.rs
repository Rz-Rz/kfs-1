#![no_std]

#[path = "memory/memory_impl.rs"]
mod memory_impl;

use memory_impl::{memcpy, memset};

#[no_mangle]
pub extern "C" fn kfs_memory_helpers_marker() -> u8 {
    let mut dst = [0u8; 4];
    let src = [1u8, 2u8, 3u8, 0u8];
    unsafe {
        memcpy(dst.as_mut_ptr(), src.as_ptr(), 3);
        memset(dst.as_mut_ptr().add(3), 0xAA, 1);
    }
    dst[0] ^ dst[1] ^ dst[2] ^ dst[3]
}
