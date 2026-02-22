#![no_std]
#![no_main]

use core::panic::PanicInfo;

const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_COLOR_LIGHT_GREEN_ON_BLACK: u16 = 0x02;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    halt_forever()
}

#[no_mangle]
pub extern "C" fn kmain() -> ! {
    // M2 marker: proves control reached Rust from ASM bootstrap.
    unsafe {
        core::ptr::write_volatile(
            VGA_TEXT_BUFFER,
            (VGA_COLOR_LIGHT_GREEN_ON_BLACK << 8) | (b'4' as u16),
        );
        core::ptr::write_volatile(
            VGA_TEXT_BUFFER.add(1),
            (VGA_COLOR_LIGHT_GREEN_ON_BLACK << 8) | (b'2' as u16),
        );
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
