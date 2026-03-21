use core::arch::asm;

#[repr(transparent)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct Port(u16);

impl Port {
    pub const fn new(value: u16) -> Self {
        Self(value)
    }

    pub const fn as_u16(self) -> u16 {
        self.0
    }

    pub const fn offset(self, delta: u16) -> Self {
        Self(self.0.wrapping_add(delta))
    }

    pub unsafe fn read_u8(self) -> u8 {
        let value: u8;
        unsafe {
            asm!(
                "in al, dx",
                in("dx") self.0,
                out("al") value,
                options(nomem, nostack, preserves_flags)
            );
        }
        value
    }

    pub unsafe fn write_u8(self, value: u8) {
        unsafe {
            asm!(
                "out dx, al",
                in("dx") self.0,
                in("al") value,
                options(nomem, nostack, preserves_flags)
            );
        }
    }
}
