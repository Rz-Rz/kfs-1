#![no_std]

#[no_mangle]
#[used]
// This marker gives the linker a small read-only value so tests can prove `.rodata` exists.
pub static KFS_RODATA_MARKER: [u8; 8] = *b"KFSRODAT";

#[no_mangle]
#[used]
// This marker gives the linker a writable value so tests can prove `.data` exists.
pub static mut KFS_DATA_MARKER: u32 = 0x1234_5678;
