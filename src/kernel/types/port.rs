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
}
