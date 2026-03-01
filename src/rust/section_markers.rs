#![no_std]

#[no_mangle]
#[used]
pub static KFS_RODATA_MARKER: [u8; 8] = *b"KFSRODAT";

#[no_mangle]
#[used]
pub static mut KFS_DATA_MARKER: u32 = 0x1234_5678;
