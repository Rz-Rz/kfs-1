#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VgaColor {
    Black = 0x0,
    Blue = 0x1,
    Green = 0x2,
    Cyan = 0x3,
    Red = 0x4,
    Magenta = 0x5,
    Brown = 0x6,
    LightGray = 0x7,
    DarkGray = 0x8,
    LightBlue = 0x9,
    LightGreen = 0xA,
    LightCyan = 0xB,
    LightRed = 0xC,
    LightMagenta = 0xD,
    Yellow = 0xE,
    White = 0xF,
}

impl VgaColor {
    pub const ALL: [Self; 16] = [
        Self::Black,
        Self::Blue,
        Self::Green,
        Self::Cyan,
        Self::Red,
        Self::Magenta,
        Self::Brown,
        Self::LightGray,
        Self::DarkGray,
        Self::LightBlue,
        Self::LightGreen,
        Self::LightCyan,
        Self::LightRed,
        Self::LightMagenta,
        Self::Yellow,
        Self::White,
    ];

    #[inline(always)]
    pub const fn code(self) -> u8 {
        self as u8
    }

    #[inline(always)]
    pub const fn from_index(index: usize) -> Self {
        Self::ALL[index & 0x0f]
    }
}

pub const BLACK: VgaColor = VgaColor::Black;
pub const RED: VgaColor = VgaColor::Red;

#[allow(non_camel_case_types)]
pub type COLOR = VgaColor;
