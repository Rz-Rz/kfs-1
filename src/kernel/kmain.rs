#![no_std]
#![no_main]

use core::panic::PanicInfo;
#[path = "vga/vga_palette.rs"]
mod vga_palette;
use vga_palette::VgaColor;

// These are Rust names for functions implemented in another module with the C ABI.
// We declare them here so `kmain` can call them.
unsafe extern "C" {
    fn vga_init();
    fn vga_set_color(foreground: u8, background: u8);
    //fn vga_printf_args(format: *const u8, args: *const usize, arg_count: usize);
    fn vga_printf(format: *const u8, value: usize);
    fn vga_puts(text: *const u8);
}

#[panic_handler]
/// This runs when Rust hits a panic.
///
/// A panic means something went badly wrong, so the safest thing for this tiny
/// kernel is to stop doing work forever.
fn panic(_info: &PanicInfo) -> ! {
    halt_forever()
}

#[no_mangle]
/// This is the first Rust function the boot code jumps into.
///
/// It prepares the VGA text writer, prints a short message, and then keeps the
/// CPU halted so the kernel does not fall into random memory.
pub extern "C" fn kmain() -> ! {
    unsafe {
        vga_init();
        let mut i: usize = 0;
        vga_puts(b"42\nTHE BEST\n\0".as_ptr());
        vga_puts(b"indexed lines:\n\0".as_ptr());
        while i < 16 {
            let color = VgaColor::from_index(i);
            vga_set_color(color.code(), VgaColor::Black.code());
            vga_printf(b"line %d\n\0".as_ptr(), i);
            i += 1;
        }
        vga_set_color(VgaColor::LightGreen.code(), VgaColor::Black.code());
    }
    halt_forever()
}

#[inline(always)]
/// This keeps the CPU in a stopped loop forever.
///
/// `cli` turns off hardware interrupts and `hlt` tells the CPU to sleep until
/// the next interrupt. Because interrupts are off, the loop stays parked.
fn halt_forever() -> ! {
    loop {
        unsafe {
            core::arch::asm!("cli", "hlt", options(nomem, nostack));
        }
    }
}
