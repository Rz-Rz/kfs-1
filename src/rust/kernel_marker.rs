#![no_std]

#[no_mangle]
/// This empty marker gives tests an easy Rust symbol to look for in the kernel.
pub extern "C" fn kfs_rust_marker() {}
