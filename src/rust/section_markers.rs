#![no_std]

#[no_mangle]
#[used]
pub static KFS_RODATA_MARKER: [u8; 8] = *b"KFSRODAT";

#[no_mangle]
#[used]
#[link_section = ".rodata.kfs_test"]
pub static KFS_RODATA_SUBSECTION_MARKER: [u8; 8] = *b"KFSR2DAT";

#[no_mangle]
#[used]
pub static mut KFS_DATA_MARKER: u32 = 0x1234_5678;

#[no_mangle]
#[used]
#[link_section = ".data.kfs_test"]
pub static mut KFS_DATA_SUBSECTION_MARKER: u32 = 0x89ab_cdef;

#[no_mangle]
#[used]
pub static mut KFS_BSS_MARKER: u32 = 0;

#[no_mangle]
#[used]
#[link_section = ".bss.kfs_test"]
pub static mut KFS_BSS_SUBSECTION_MARKER: u32 = 0;
