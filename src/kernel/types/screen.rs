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
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct ScreenPosition {
    row: usize,
    col: usize,
}

impl ScreenPosition {
    pub const fn new(row: usize, col: usize) -> Self {
        Self { row, col }
    }

    pub const fn row(self) -> usize {
        self.row
    }

    pub const fn col(self) -> usize {
        self.col
    }
}

#[repr(transparent)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct ColorCode(u8);

impl ColorCode {
    pub const fn new(value: u8) -> Self {
        Self(value)
    }

    pub const fn as_u8(self) -> u8 {
        self.0
    }
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

pub const VGA_TEXT_DIMENSIONS: ScreenDimensions = ScreenDimensions::new(80, 25);
