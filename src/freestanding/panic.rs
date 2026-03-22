use core::panic::PanicInfo;

use crate::kernel::core::entry;
use crate::kernel::services::diagnostics;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    if entry::is_test_mode() {
        diagnostics::initialize();
        diagnostics::write_line("PANIC");
        entry::qemu_exit(0x11);
    }

    entry::halt_forever()
}
