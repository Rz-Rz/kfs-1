use crate::kernel::drivers::serial;

pub(crate) fn initialize() {
    serial::initialize();
}

pub(crate) fn write_line(message: &str) {
    write(message);
    write("\n");
}

fn write(message: &str) {
    for byte in message.bytes() {
        serial::write_byte(byte);
    }
}
