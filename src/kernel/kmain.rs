#![no_std]
#![no_main]

use core::panic::PanicInfo;

unsafe extern "C" {
    fn vga_init();
    fn vga_puts(text: *const u8);
}

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    halt_forever()
}

#[no_mangle]
pub extern "C" fn kmain() -> ! {
    unsafe {
        vga_init();
        vga_puts(b"42\0".as_ptr());
        vga_puts(b"THE BEST".as_ptr());
    }
    halt_forever()
}

#[inline(always)]
fn halt_forever() -> ! {
    loop {
        unsafe {
            core::arch::asm!("cli", "hlt", options(nomem, nostack));
        }
    }
}
