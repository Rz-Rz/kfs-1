mod writer;

use crate::kernel::types::screen::{
    ColorCode, CursorPos, ScreenDimensions, ScreenPosition, VgaColor, VGA_TEXT_DIMENSIONS,
};

pub const VGA_TEXT_DEFAULT_COLOR: ColorCode =
    ColorCode::vga(VgaColor::Green.code(), VgaColor::Black.code());
pub const VGA_TEXT_BLANK_BYTE: u8 = b' ';
pub const VGA_TEXT_HISTORY_ROWS: usize = 256;
pub const VGA_TEXT_HISTORY_DIMENSIONS: ScreenDimensions =
    ScreenDimensions::new(VGA_TEXT_DIMENSIONS.width(), VGA_TEXT_HISTORY_ROWS);
pub const VGA_TEXT_HISTORY_CELL_COUNT: usize = VGA_TEXT_HISTORY_ROWS * VGA_TEXT_DIMENSIONS.width();
pub const VGA_TEXT_TERMINAL_COUNT: usize = 12;
pub const VGA_TEXT_TERMINAL_LABEL_WIDTH: usize = 7;

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

        VgaPutResult {
            cell_index,
            scrolled,
        }
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
            unsafe {
                *self.history.get_unchecked_mut(cell_index) = vga_text_cell(self.color, byte);
            }
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
        let width = VGA_TEXT_DIMENSIONS.width();
        let mut cell_index: Option<usize> = self.cursor.backspace_cell();

        if cell_index.is_none() {
            cell_index = self.backspace_previous_line_last_non_blank(width);
        }

        if let Some(index) = cell_index {
            unsafe {
                *self.history.get_unchecked_mut(index) =
                    vga_text_cell(self.color, VGA_TEXT_BLANK_BYTE);
            }
        }
        self.viewport_top = vga_text_tail_viewport_top(self.cursor.row);
    }

    fn backspace_previous_line_last_non_blank(&mut self, width: usize) -> Option<usize> {
        if self.cursor.row == 0 || width == 0 {
            return None;
        }

        let previous_row = self.cursor.row - 1;
        let row_start = previous_row * width;

        let mut col = width;
        while col > 0 {
            col -= 1;

            let index = row_start + col;
            let cell = unsafe { *self.history.get_unchecked(index) };
            if (cell & 0x00ff) != (VGA_TEXT_BLANK_BYTE as u16) {
                self.cursor.row = previous_row;
                self.cursor.col = col;
                return Some(index);
            }
        }

        None
    }

    fn fill_history(&mut self, value: u16) {
        let mut idx = 0;
        while idx < self.history.len() {
            unsafe {
                *self.history.get_unchecked_mut(idx) = value;
            }
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
            unsafe {
                *self.active_slots.get_unchecked_mut(idx) = idx;
                self.terminals.get_unchecked_mut(idx).reset();
            }
            idx += 1;
        }
    }

    pub fn active(&self) -> &VgaTerminal {
        unsafe { self.terminals.get_unchecked(self.active_slot()) }
    }

    pub fn active_mut(&mut self) -> &mut VgaTerminal {
        let slot = self.active_slot();
        unsafe { self.terminals.get_unchecked_mut(slot) }
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

        unsafe {
            self.terminals.get_unchecked_mut(slot).reset();
            *self.active_slots.get_unchecked_mut(self.active_count) = slot;
        }
        self.active_index = self.active_count;
        self.active_count += 1;
        true
    }

    pub fn destroy_active_terminal(&mut self) -> bool {
        if self.active_count <= 1 {
            return false;
        }

        let freed_slot = self.active_slot();
        unsafe {
            self.terminals.get_unchecked_mut(freed_slot).reset();
        }

        let mut idx = self.active_index;
        while idx + 1 < self.active_count {
            unsafe {
                *self.active_slots.get_unchecked_mut(idx) =
                    *self.active_slots.get_unchecked(idx + 1);
            }
            idx += 1;
        }

        self.active_count -= 1;
        unsafe {
            *self.active_slots.get_unchecked_mut(self.active_count) = freed_slot;
        }
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
        unsafe { *self.active_slots.get_unchecked(self.active_index) }
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
            if unsafe { *self.active_slots.get_unchecked(idx) } == slot {
                return true;
            }
            idx += 1;
        }
        false
    }
}

pub fn terminal_label(index: usize) -> &'static [u8] {
    match index.min(VGA_TEXT_TERMINAL_COUNT - 1) {
        0 => b"alpha",
        1 => b"beta",
        2 => b"gamma",
        3 => b"delta",
        4 => b"epsilon",
        5 => b"zeta",
        6 => b"eta",
        7 => b"theta",
        8 => b"iota",
        9 => b"kappa",
        10 => b"lambda",
        _ => b"mu",
    }
}

fn terminal_label_overlay(index: usize) -> &'static [u8; VGA_TEXT_TERMINAL_LABEL_WIDTH] {
    match index.min(VGA_TEXT_TERMINAL_COUNT - 1) {
        0 => b"  alpha",
        1 => b"   beta",
        2 => b"  gamma",
        3 => b"  delta",
        4 => b"epsilon",
        5 => b"   zeta",
        6 => b"    eta",
        7 => b"  theta",
        8 => b"   iota",
        9 => b"  kappa",
        10 => b" lambda",
        _ => b"     mu",
    }
}

pub fn build_terminal_label_cells(
    label_index: usize,
    color: ColorCode,
) -> [u16; VGA_TEXT_TERMINAL_LABEL_WIDTH] {
    let label = terminal_label_overlay(label_index);
    let mut cells = [0u16; VGA_TEXT_TERMINAL_LABEL_WIDTH];
    let mut idx = 0;
    while idx < VGA_TEXT_TERMINAL_LABEL_WIDTH {
        unsafe {
            *cells.get_unchecked_mut(idx) = vga_text_cell(color, *label.get_unchecked(idx));
        }
        idx += 1;
    }

    cells
}

// Alternate logical layouts are centered inside the fixed VGA framebuffer so rows stay readable.
pub const fn screen_render_origin(
    logical_dimensions: ScreenDimensions,
    physical_dimensions: ScreenDimensions,
) -> ScreenPosition {
    ScreenPosition::new(
        physical_dimensions
            .height()
            .saturating_sub(logical_dimensions.height())
            / 2,
        physical_dimensions
            .width()
            .saturating_sub(logical_dimensions.width())
            / 2,
    )
}

pub const fn vga_text_tail_viewport_top(cursor_row: usize) -> usize {
    VGA_TEXT_DIMENSIONS.tail_viewport_top(cursor_row)
}

pub fn vga_text_cell<C: Into<ColorCode>>(color: C, byte: u8) -> u16 {
    let color = color.into();
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
        unsafe {
            *buffer.get_unchecked_mut(cursor) = vga_text_cell(color, byte);
        }
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
        unsafe {
            *buffer.get_unchecked_mut(idx) = *buffer.get_unchecked(idx + row_width);
        }
        idx += 1;
    }

    while idx < total_cells {
        unsafe {
            *buffer.get_unchecked_mut(idx) = blank;
        }
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
                unsafe {
                    *screen.get_unchecked_mut(screen_start + col) =
                        *history.get_unchecked(history_start + col);
                }
                col += 1;
            }
        } else {
            while col < row_width {
                unsafe {
                    *screen.get_unchecked_mut(screen_start + col) = blank;
                }
                col += 1;
            }
        }

        screen_row += 1;
    }
}

pub fn render_logical_screen_to_physical<T: Copy>(
    logical_dimensions: ScreenDimensions,
    physical_dimensions: ScreenDimensions,
    logical_screen: &[T],
    physical_screen: &mut [T],
    blank: T,
) {
    let physical_cells = physical_dimensions.cell_count();
    if physical_screen.len() < physical_cells {
        return;
    }

    let logical_cells = logical_dimensions.cell_count();
    if logical_screen.len() < logical_cells {
        return;
    }

    let origin = screen_render_origin(logical_dimensions, physical_dimensions);
    let copy_width = logical_dimensions.width().min(physical_dimensions.width());
    let copy_height = logical_dimensions
        .height()
        .min(physical_dimensions.height());
    let mut idx = 0;
    while idx < physical_cells {
        unsafe {
            *physical_screen.get_unchecked_mut(idx) = blank;
        }
        idx += 1;
    }

    let mut row = 0;
    while row < copy_height {
        let logical_row_start = row * logical_dimensions.width();
        let physical_row_start = physical_dimensions.cell_index(origin.row() + row, origin.col());
        let mut col = 0;
        while col < copy_width {
            unsafe {
                *physical_screen.get_unchecked_mut(physical_row_start + col) =
                    *logical_screen.get_unchecked(logical_row_start + col);
            }
            col += 1;
        }
        row += 1;
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
