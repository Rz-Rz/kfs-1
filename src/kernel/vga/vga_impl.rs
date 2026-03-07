pub const VGA_WIDTH: usize = 80;
pub const VGA_HEIGHT: usize = 25;
pub const VGA_CELLS: usize = VGA_WIDTH * VGA_HEIGHT;
pub const VGA_DEFAULT_FOREGROUND: u8 = 0x02;
pub const VGA_DEFAULT_BACKGROUND: u8 = 0x00;
pub const VGA_DEFAULT_ATTRIBUTE: u8 =
    vga_attribute(VGA_DEFAULT_FOREGROUND, VGA_DEFAULT_BACKGROUND);

/// This keeps only the low 4 bits used by VGA color values.
pub const fn vga_color_nibble(color: u8) -> u8 {
    color & 0x0f
}

/// This packs VGA foreground/background colors into one attribute byte.
pub const fn vga_attribute(foreground: u8, background: u8) -> u8 {
    (vga_color_nibble(background) << 4) | vga_color_nibble(foreground)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VgaPutResult {
    pub cell_index: Option<usize>,
    pub scrolled: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VgaCursor {
    pub row: usize,
    pub col: usize,
}

impl VgaCursor {
    /// This makes a brand-new cursor at the top-left corner.
    pub const fn new() -> Self {
        Self { row: 0, col: 0 }
    }

    /// This updates the cursor after one incoming byte.
    ///
    /// For normal text, it returns the screen cell that should be written.
    /// For a newline, it only moves the cursor and returns `None`.
    pub fn put_byte(&mut self, byte: u8) -> VgaPutResult {
        if byte == b'\n' {
            return VgaPutResult {
                cell_index: None,
                scrolled: self.advance_row(),
            };
        }

        let cell_index = self.cell_index();
        self.col += 1;
        let scrolled = if self.col >= VGA_WIDTH {
            self.advance_row()
        } else {
            false
        };

        VgaPutResult {
            cell_index: Some(cell_index),
            scrolled,
        }
    }

    /// This turns the current row and column into one flat screen index.
    ///
    /// VGA text memory is laid out in one long line of cells, so we convert a
    /// two-number position into one number here.
    fn cell_index(&self) -> usize {
        (self.row * VGA_WIDTH) + self.col
    }

    /// This moves the cursor to the start of the next row.
    ///
    /// When the cursor goes past the bottom of the screen, it stays on the
    /// last row and tells the caller that the visible buffer must scroll.
    fn advance_row(&mut self) -> bool {
        self.col = 0;
        if self.row + 1 >= VGA_HEIGHT {
            self.row = VGA_HEIGHT - 1;
            return true;
        }
        self.row += 1;
        false
    }
}

/// This scrolls a text buffer up by one row and clears the last row.
pub fn scroll_buffer<T: Copy>(buffer: &mut [T], blank: T) {
    if buffer.len() < VGA_CELLS {
        return;
    }

    let mut idx: usize = 0;
    while idx + VGA_WIDTH < VGA_CELLS {
        buffer[idx] = buffer[idx + VGA_WIDTH];
        idx += 1;
    }

    while idx < VGA_CELLS {
        buffer[idx] = blank;
        idx += 1;
    }
}
