#![no_std]

#[path = "memory/memory_impl.rs"]
mod memory_impl;

use memory_impl::{memcpy, memset};

#[no_mangle]
/// This marker proves the memory helper module was linked into the kernel.
///
/// It performs one small copy and one small fill so tests can confirm these
/// helpers exist in the final binary.
pub extern "C" fn kfs_memory_helpers_marker() -> u8 {
    let mut dst = [0u8; 4];
    let src = [1u8, 2u8, 3u8, 0u8];
    unsafe {
        memcpy(dst.as_mut_ptr(), src.as_ptr(), 3);
        memset(dst.as_mut_ptr().add(3), 0xAA, 1);
    }
    dst[0] ^ dst[1] ^ dst[2] ^ dst[3]
}
