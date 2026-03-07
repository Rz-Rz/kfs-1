pub const VGA_WIDTH: usize = 80;
pub const VGA_HEIGHT: usize = 25;

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
    pub fn put_byte(&mut self, byte: u8) -> Option<usize> {
        if byte == b'\n' {
            self.advance_row();
            return None;
        }

        let cell_index = self.cell_index();
        self.col += 1;
        if self.col >= VGA_WIDTH {
            self.advance_row();
        }

        Some(cell_index)
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
    /// When the cursor goes past the bottom of the screen, it wraps back to
    /// the top instead of scrolling.
    fn advance_row(&mut self) {
        self.col = 0;
        self.row += 1;
        if self.row >= VGA_HEIGHT {
            self.row = 0;
        }
    }
}
