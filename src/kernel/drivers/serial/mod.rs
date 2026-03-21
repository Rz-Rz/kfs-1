use crate::kernel::machine::port::Port;

const COM1_DATA: Port = Port::new(0x3f8);
const COM1_INTERRUPT_ENABLE: Port = Port::new(0x3f8).offset(1);
const COM1_FIFO_CONTROL: Port = Port::new(0x3f8).offset(2);
const COM1_LINE_CONTROL: Port = Port::new(0x3f8).offset(3);
const COM1_MODEM_CONTROL: Port = Port::new(0x3f8).offset(4);
const COM1_LINE_STATUS: Port = Port::new(0x3f8).offset(5);

pub(crate) fn initialize() {
    unsafe {
        COM1_INTERRUPT_ENABLE.write_u8(0x00);
        COM1_LINE_CONTROL.write_u8(0x80);
        COM1_DATA.write_u8(0x03);
        COM1_INTERRUPT_ENABLE.write_u8(0x00);
        COM1_LINE_CONTROL.write_u8(0x03);
        COM1_FIFO_CONTROL.write_u8(0xc7);
        COM1_MODEM_CONTROL.write_u8(0x03);
    }
}

pub(crate) fn write_byte(byte: u8) {
    unsafe {
        while COM1_LINE_STATUS.read_u8() & 0x20 == 0 {}
        COM1_DATA.write_u8(byte);
    }
}
