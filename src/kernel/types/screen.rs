#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct ScreenDimensions {
    width: usize,
    height: usize,
}

impl ScreenDimensions {
    pub const fn new(width: usize, height: usize) -> Self {
        Self { width, height }
    }

    pub const fn width(self) -> usize {
        self.width
    }

    pub const fn height(self) -> usize {
        self.height
    }

    pub const fn cell_count(self) -> usize {
        self.width * self.height
    }

    pub const fn row_cells(self, row_count: usize) -> usize {
        self.width.saturating_mul(row_count)
    }

    pub const fn clamp_row(self, row: usize) -> usize {
        if row > self.last_row() {
            self.last_row()
        } else {
            row
        }
    }

    pub const fn clamp_col(self, col: usize) -> usize {
        if col > self.last_col() {
            self.last_col()
        } else {
            col
        }
    }

    pub const fn cell_index(self, row: usize, col: usize) -> usize {
        row.saturating_mul(self.width).saturating_add(col)
    }

    pub const fn last_row(self) -> usize {
        self.height.saturating_sub(1)
    }

    pub const fn last_col(self) -> usize {
        self.width.saturating_sub(1)
    }

    pub const fn tail_viewport_top(self, cursor_row: usize) -> usize {
        cursor_row.saturating_sub(self.height.saturating_sub(1))
    }
}

#[repr(transparent)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct ColorCode(u8);

impl ColorCode {
    pub const fn new(value: u8) -> Self {
        Self(value)
    }

    pub const fn vga(foreground: u8, background: u8) -> Self {
        Self(vga_attribute(foreground, background))
    }

    pub const fn as_u8(self) -> u8 {
        self.0
    }
}

impl From<u8> for ColorCode {
    fn from(value: u8) -> Self {
        Self::new(value)
    }
}

#[repr(u8)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
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

    pub const fn code(self) -> u8 {
        self as u8
    }

    pub const fn from_index(index: usize) -> Self {
        Self::ALL[index & 0x0f]
    }
}

pub const fn vga_color_nibble(color: u8) -> u8 {
    color & 0x0f
}

pub const fn vga_attribute(foreground: u8, background: u8) -> u8 {
    (vga_color_nibble(background) << 4) | vga_color_nibble(foreground)
}

#[repr(C)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct ScreenCell {
    pub color: ColorCode,
    pub byte: u8,
}

impl ScreenCell {
    pub const fn new(color: ColorCode, byte: u8) -> Self {
        Self { color, byte }
    }
}

#[repr(C)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct CursorPos {
    pub row: usize,
    pub col: usize,
}

impl CursorPos {
    pub const fn new(row: usize, col: usize) -> Self {
        Self { row, col }
    }
}

// The VGA text driver always targets the standard 80x25 text-mode geometry.
pub const VGA_TEXT_DIMENSIONS: ScreenDimensions = ScreenDimensions::new(80, 25);
