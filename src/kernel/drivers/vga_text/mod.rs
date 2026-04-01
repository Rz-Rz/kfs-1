mod writer;

use crate::kernel::types::screen::{ColorCode, CursorPos, ScreenDimensions, VgaColor, VGA_TEXT_DIMENSIONS};

pub const VGA_TEXT_DEFAULT_COLOR: ColorCode =
    ColorCode::vga(VgaColor::Green.code(), VgaColor::Black.code());
pub const VGA_TEXT_BLANK_BYTE: u8 = b' ';
pub const VGA_TEXT_HISTORY_ROWS: usize = 256;
pub const VGA_TEXT_HISTORY_DIMENSIONS: ScreenDimensions =
    ScreenDimensions::new(VGA_TEXT_DIMENSIONS.width(), VGA_TEXT_HISTORY_ROWS);
pub const VGA_TEXT_HISTORY_CELL_COUNT: usize = VGA_TEXT_HISTORY_ROWS * VGA_TEXT_DIMENSIONS.width();
pub const VGA_TEXT_TERMINAL_COUNT: usize = 12;
pub const VGA_TEXT_TERMINAL_LABEL_WIDTH: usize = 7;
pub const VGA_TEXT_TERMINAL_LABELS: [&[u8]; VGA_TEXT_TERMINAL_COUNT] = [
    b"alpha",
    b"beta",
    b"gamma",
    b"delta",
    b"epsilon",
    b"zeta",
    b"eta",
    b"theta",
    b"iota",
    b"kappa",
    b"lambda",
    b"mu",
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VgaPutResult {
    pub cell_index: Option<usize>,
    pub scrolled: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VgaHistoryCursor {
    pub row: usize,
    pub col: usize,
}

impl VgaHistoryCursor {
    pub const fn new() -> Self {
        Self { row: 0, col: 0 }
    }

    pub fn move_to(&mut self, row: usize, col: usize) {
        self.row = VGA_TEXT_HISTORY_DIMENSIONS.clamp_row(row);
        self.col = VGA_TEXT_HISTORY_DIMENSIONS.clamp_col(col);
    }

    pub fn put_byte(&mut self, byte: u8) -> VgaPutResult {
        if byte == b'\n' {
            return VgaPutResult {
                cell_index: None,
                scrolled: self.advance_row(),
            };
        }

        let cell_index = Some(self.cell_index());
        self.col += 1;

        let scrolled = if self.col >= VGA_TEXT_HISTORY_DIMENSIONS.width() {
            self.advance_row()
        } else {
            false
        };

        VgaPutResult { cell_index, scrolled }
    }

    pub fn backspace_cell(&mut self) -> Option<usize> {
        if self.col == 0 {
            return None;
        }

        self.col -= 1;
        Some(self.cell_index())
    }

    fn cell_index(&self) -> usize {
        VGA_TEXT_HISTORY_DIMENSIONS.cell_index(self.row, self.col)
    }

    fn advance_row(&mut self) -> bool {
        self.col = 0;
        if self.row + 1 >= VGA_TEXT_HISTORY_DIMENSIONS.height() {
            self.row = VGA_TEXT_HISTORY_DIMENSIONS.last_row();
            return true;
        }
        self.row += 1;
        false
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VgaTerminal {
    pub cursor: VgaHistoryCursor,
    pub viewport_top: usize,
    pub color: ColorCode,
    pub history: [u16; VGA_TEXT_HISTORY_CELL_COUNT],
}

impl VgaTerminal {
    pub const fn new() -> Self {
        Self {
            cursor: VgaHistoryCursor::new(),
            viewport_top: 0,
            color: VGA_TEXT_DEFAULT_COLOR,
            history: [0; VGA_TEXT_HISTORY_CELL_COUNT],
        }
    }

    pub fn reset(&mut self) {
        self.cursor = VgaHistoryCursor::new();
        self.viewport_top = 0;
        self.color = VGA_TEXT_DEFAULT_COLOR;
        self.fill_history(vga_text_cell(self.color, VGA_TEXT_BLANK_BYTE));
    }

    pub fn move_cursor(&mut self, row: usize, col: usize) {
        self.cursor.move_to(row, col);
        self.viewport_top = vga_text_tail_viewport_top(self.cursor.row);
    }

    pub fn viewport_up(&mut self) {
        if self.viewport_top > 0 {
            self.viewport_top -= 1;
        }
    }

    pub fn viewport_down(&mut self) {
        let tail_top = vga_text_tail_viewport_top(self.cursor.row);
        if self.viewport_top < tail_top {
            self.viewport_top += 1;
        }
    }

    pub fn put_byte(&mut self, byte: u8) {
        let result = self.cursor.put_byte(byte);
        if let Some(cell_index) = result.cell_index {
            self.history[cell_index] = vga_text_cell(self.color, byte);
        }
        if result.scrolled {
            vga_text_scroll_rows_up(
                &mut self.history,
                VGA_TEXT_DIMENSIONS.width(),
                VGA_TEXT_HISTORY_ROWS,
                vga_text_cell(self.color, VGA_TEXT_BLANK_BYTE),
            );
        }
        self.viewport_top = vga_text_tail_viewport_top(self.cursor.row);
    }

    pub fn put_bytes(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            self.put_byte(byte);
        }
    }

    pub fn backspace(&mut self) {
        if let Some(cell_index) = self.cursor.backspace_cell() {
            self.history[cell_index] = vga_text_cell(self.color, VGA_TEXT_BLANK_BYTE);
        }
        self.viewport_top = vga_text_tail_viewport_top(self.cursor.row);
    }

    fn fill_history(&mut self, value: u16) {
        let mut idx = 0;
        while idx < self.history.len() {
            self.history[idx] = value;
            idx += 1;
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VgaTerminalBank {
    pub active_index: usize,
    pub active_count: usize,
    pub active_slots: [usize; VGA_TEXT_TERMINAL_COUNT],
    pub terminals: [VgaTerminal; VGA_TEXT_TERMINAL_COUNT],
}

impl VgaTerminalBank {
    pub const fn new() -> Self {
        const EMPTY_TERMINAL: VgaTerminal = VgaTerminal::new();
        Self {
            active_index: 0,
            active_count: 1,
            active_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
            terminals: [EMPTY_TERMINAL; VGA_TEXT_TERMINAL_COUNT],
        }
    }

    pub fn reset(&mut self) {
        self.active_index = 0;
        self.active_count = 1;
        let mut idx = 0;
        while idx < VGA_TEXT_TERMINAL_COUNT {
            self.active_slots[idx] = idx;
            self.terminals[idx].reset();
            idx += 1;
        }
    }

    pub fn active(&self) -> &VgaTerminal {
        &self.terminals[self.active_slot()]
    }

    pub fn active_mut(&mut self) -> &mut VgaTerminal {
        let slot = self.active_slot();
        &mut self.terminals[slot]
    }

    pub fn terminal(&self, index: usize) -> Option<&VgaTerminal> {
        self.terminals.get(index)
    }

    pub fn terminal_mut(&mut self, index: usize) -> Option<&mut VgaTerminal> {
        self.terminals.get_mut(index)
    }

    pub fn set_active(&mut self, index: usize) -> bool {
        if index >= self.active_count {
            return false;
        }

        self.active_index = index;
        true
    }

    pub fn create_terminal(&mut self) -> bool {
        if self.active_count >= VGA_TEXT_TERMINAL_COUNT {
            return false;
        }

        let Some(slot) = self.first_free_slot() else {
            return false;
        };

        self.terminals[slot].reset();
        self.active_slots[self.active_count] = slot;
        self.active_index = self.active_count;
        self.active_count += 1;
        true
    }

    pub fn destroy_active_terminal(&mut self) -> bool {
        if self.active_count <= 1 {
            return false;
        }

        let freed_slot = self.active_slot();
        self.terminals[freed_slot].reset();

        let mut idx = self.active_index;
        while idx + 1 < self.active_count {
            self.active_slots[idx] = self.active_slots[idx + 1];
            idx += 1;
        }

        self.active_count -= 1;
        self.active_slots[self.active_count] = freed_slot;
        if self.active_index >= self.active_count {
            self.active_index = self.active_count - 1;
        }
        true
    }

    pub fn active_label_index(&self) -> usize {
        self.active_index
    }

    pub fn active_count(&self) -> usize {
        self.active_count
    }

    pub fn active_slot(&self) -> usize {
        self.active_slots[self.active_index]
    }

    fn first_free_slot(&self) -> Option<usize> {
        let mut slot = 0;
        while slot < VGA_TEXT_TERMINAL_COUNT {
            if !self.is_slot_active(slot) {
                return Some(slot);
            }
            slot += 1;
        }
        None
    }

    fn is_slot_active(&self, slot: usize) -> bool {
        let mut idx = 0;
        while idx < self.active_count {
            if self.active_slots[idx] == slot {
                return true;
            }
            idx += 1;
        }
        false
    }
}

pub fn terminal_label(index: usize) -> &'static [u8] {
    VGA_TEXT_TERMINAL_LABELS[index.min(VGA_TEXT_TERMINAL_COUNT - 1)]
}

pub fn build_terminal_label_cells(label_index: usize, color: ColorCode) -> [u16; VGA_TEXT_TERMINAL_LABEL_WIDTH] {
    let blank = vga_text_cell(color, VGA_TEXT_BLANK_BYTE);
    let mut cells = [blank; VGA_TEXT_TERMINAL_LABEL_WIDTH];
    let label = terminal_label(label_index);
    let start = VGA_TEXT_TERMINAL_LABEL_WIDTH.saturating_sub(label.len());
    let mut idx = 0;

    while idx < label.len() && start + idx < VGA_TEXT_TERMINAL_LABEL_WIDTH {
        cells[start + idx] = vga_text_cell(color, label[idx]);
        idx += 1;
    }

    cells
}

pub const fn vga_text_tail_viewport_top(cursor_row: usize) -> usize {
    VGA_TEXT_DIMENSIONS.tail_viewport_top(cursor_row)
}

pub fn vga_text_cell(color: ColorCode, byte: u8) -> u16 {
    ((color.as_u8() as u16) << 8) | (byte as u16)
}

pub fn vga_text_normalize_cursor(cursor: usize, cell_count: usize) -> usize {
    if cell_count == 0 || cursor >= cell_count {
        return 0;
    }

    cursor
}

pub fn vga_text_write_cells(
    buffer: &mut [u16],
    cursor: usize,
    color: ColorCode,
    bytes: &[u8],
) -> usize {
    if buffer.is_empty() {
        return 0;
    }

    let mut cursor = vga_text_normalize_cursor(cursor, buffer.len());

    for &byte in bytes {
        buffer[cursor] = vga_text_cell(color, byte);
        cursor += 1;
        if cursor >= buffer.len() {
            cursor = 0;
        }
    }

    cursor
}

pub fn vga_text_normalize_cursor_pos(cursor: CursorPos, dimensions: ScreenDimensions) -> CursorPos {
    if dimensions.width() == 0 || dimensions.height() == 0 {
        return CursorPos::new(0, 0);
    }

    let row = if cursor.row >= dimensions.height() {
        dimensions.height() - 1
    } else {
        cursor.row
    };
    let col = if cursor.col >= dimensions.width() {
        dimensions.width() - 1
    } else {
        cursor.col
    };

    CursorPos::new(row, col)
}

pub fn vga_text_write_screen(
    buffer: &mut [u16],
    dimensions: ScreenDimensions,
    cursor: CursorPos,
    color: ColorCode,
    bytes: &[u8],
) -> CursorPos {
    if buffer.is_empty() || dimensions.width() == 0 || dimensions.height() == 0 {
        return CursorPos::new(0, 0);
    }

    if buffer.len() < dimensions.cell_count() {
        return CursorPos::new(0, 0);
    }

    let blank = vga_text_cell(color, VGA_TEXT_BLANK_BYTE);
    let mut cursor = vga_text_normalize_cursor_pos(cursor, dimensions);

    for &byte in bytes {
        if byte == b'\n' {
            cursor = vga_text_advance_line(buffer, dimensions, cursor, blank);
            continue;
        }

        let index = vga_text_cursor_index(dimensions, cursor);
        unsafe {
            *buffer.get_unchecked_mut(index) = vga_text_cell(color, byte);
        }

        let next_col = cursor.col + 1;
        if next_col >= dimensions.width() {
            cursor = vga_text_advance_line(buffer, dimensions, cursor, blank);
            continue;
        }

        cursor = CursorPos::new(cursor.row, next_col);
    }

    cursor
}

pub fn vga_text_scroll_rows_up<T: Copy>(
    buffer: &mut [T],
    row_width: usize,
    row_count: usize,
    blank: T,
) {
    let total_cells = row_width.saturating_mul(row_count);
    if row_width == 0 || buffer.len() < total_cells {
        return;
    }

    let mut idx = 0;
    while idx + row_width < total_cells {
        buffer[idx] = buffer[idx + row_width];
        idx += 1;
    }

    while idx < total_cells {
        buffer[idx] = blank;
        idx += 1;
    }
}

pub fn vga_text_blit_viewport<T: Copy>(
    history: &[T],
    row_width: usize,
    viewport_height: usize,
    viewport_top: usize,
    screen: &mut [T],
    blank: T,
) {
    let screen_cells = row_width.saturating_mul(viewport_height);
    if row_width == 0 || screen.len() < screen_cells {
        return;
    }

    let history_rows = history.len() / row_width;
    let mut screen_row = 0;

    while screen_row < viewport_height {
        let history_row = viewport_top + screen_row;
        let screen_start = screen_row * row_width;
        let mut col = 0;

        if history_row < history_rows {
            let history_start = history_row * row_width;
            while col < row_width {
                screen[screen_start + col] = history[history_start + col];
                col += 1;
            }
        } else {
            while col < row_width {
                screen[screen_start + col] = blank;
                col += 1;
            }
        }

        screen_row += 1;
    }
}

fn vga_text_cursor_index(dimensions: ScreenDimensions, cursor: CursorPos) -> usize {
    (cursor.row * dimensions.width()) + cursor.col
}

fn vga_text_advance_line(
    buffer: &mut [u16],
    dimensions: ScreenDimensions,
    cursor: CursorPos,
    blank: u16,
) -> CursorPos {
    let next_row = cursor.row + 1;
    if next_row < dimensions.height() {
        return CursorPos::new(next_row, 0);
    }

    vga_text_scroll_up(buffer, dimensions, blank);
    CursorPos::new(dimensions.height() - 1, 0)
}

fn vga_text_scroll_up(buffer: &mut [u16], dimensions: ScreenDimensions, blank: u16) {
    let width = dimensions.width();
    let height = dimensions.height();

    for row in 1..height {
        let dst_start = (row - 1) * width;
        let src_start = row * width;
        for col in 0..width {
            unsafe {
                let value = *buffer.get_unchecked(src_start + col);
                *buffer.get_unchecked_mut(dst_start + col) = value;
            }
        }
    }

    let last_row_start = (height - 1) * width;
    for col in 0..width {
        unsafe {
            *buffer.get_unchecked_mut(last_row_start + col) = blank;
        }
    }
}

pub(crate) fn write_bytes(bytes: &[u8]) {
    writer::write_bytes(bytes);
}

pub fn vga_text_backspace() {
    writer::backspace();
}

pub fn vga_text_viewport_up() {
    writer::viewport_up();
}

pub fn vga_text_viewport_down() {
    writer::viewport_down();
}

pub fn vga_text_set_cursor(row: usize, col: usize) {
    writer::set_cursor(row, col);
}

pub fn vga_text_set_color(foreground: u8, background: u8) {
    writer::set_color(ColorCode::vga(foreground, background));
}

pub fn vga_text_get_color() -> ColorCode {
    writer::color()
}

pub fn vga_text_set_active_terminal(index: usize) -> bool {
    writer::set_active_terminal(index)
}

pub fn vga_text_create_terminal() -> bool {
    writer::create_terminal()
}

pub fn vga_text_destroy_terminal() -> bool {
    writer::destroy_active_terminal()
}
