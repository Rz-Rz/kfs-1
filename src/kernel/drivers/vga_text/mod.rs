mod writer;

use crate::kernel::types::screen::{
    ColorCode, CursorPos, ScreenDimensions, ScreenPosition, VgaColor, VGA_TEXT_DIMENSIONS,
};

// This module keeps a larger logical text history than the hardware can show at once.
// The writer layer later picks a viewport out of that history and paints it into the
// real VGA framebuffer.
pub const VGA_TEXT_DEFAULT_COLOR: ColorCode =
    ColorCode::vga(VgaColor::Green.code(), VgaColor::Black.code());
pub const VGA_TEXT_BLANK_BYTE: u8 = b' ';
pub const VGA_TEXT_HISTORY_ROWS: usize = 256;
pub const VGA_TEXT_HISTORY_DIMENSIONS: ScreenDimensions =
    ScreenDimensions::new(VGA_TEXT_DIMENSIONS.width(), VGA_TEXT_HISTORY_ROWS);
pub const VGA_TEXT_HISTORY_CELL_COUNT: usize = VGA_TEXT_HISTORY_ROWS * VGA_TEXT_DIMENSIONS.width();
pub const VGA_TEXT_TERMINAL_COUNT: usize = 12;
pub const VGA_TEXT_TERMINAL_LABEL_WIDTH: usize = 7;
pub const VGA_TEXT_TAB_SPACES: usize = 4;

// Result of "feed one byte into the history cursor".
// We need both pieces of information: where the byte should land, and whether that
// write pushed the logical history far enough that we must scroll stored rows up.
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

// Attach the history-cursor behavior to the cursor state itself.
impl VgaHistoryCursor {
    pub const fn new() -> Self {
        Self { row: 0, col: 0 }
    }

    pub fn move_to(&mut self, row: usize, col: usize) {
        self.row = VGA_TEXT_HISTORY_DIMENSIONS.clamp_row(row);
        self.col = VGA_TEXT_HISTORY_DIMENSIONS.clamp_col(col);
    }

    pub fn put_byte(&mut self, byte: u8) -> VgaPutResult {
        // Newlines advance the cursor without writing a visible cell.
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
        // This only handles "back up within the current row". Crossing to the
        // previous row is handled one layer up, where line-length history exists.
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

// One logical terminal keeps its own history, cursor, viewport, and current color.
// That way switching terminals is just "pick another saved screen", not "rebuild it".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VgaTerminal {
    pub cursor: VgaHistoryCursor,
    pub viewport_top: usize,
    pub color: ColorCode,
    pub history: [u16; VGA_TEXT_HISTORY_CELL_COUNT],
    pub line_lengths: [usize; VGA_TEXT_HISTORY_ROWS],
}

impl VgaTerminal {
    pub const fn new() -> Self {
        Self {
            cursor: VgaHistoryCursor::new(),
            viewport_top: 0,
            color: VGA_TEXT_DEFAULT_COLOR,
            history: [0; VGA_TEXT_HISTORY_CELL_COUNT],
            line_lengths: [0; VGA_TEXT_HISTORY_ROWS],
        }
    }

    pub fn reset(&mut self) {
        self.cursor = VgaHistoryCursor::new();
        self.viewport_top = 0;
        self.color = VGA_TEXT_DEFAULT_COLOR;
        self.fill_history(vga_text_cell(self.color, VGA_TEXT_BLANK_BYTE));
        self.fill_line_lengths(0);
    }

    pub fn move_cursor(&mut self, row: usize, col: usize) {
        self.cursor.move_to(row, col);
        let cursor_row = self.cursor.row;
        unsafe {
            // If code moves the cursor to the right, treat that as extending the line.
            let line_length = self.line_lengths.get_unchecked_mut(cursor_row);
            *line_length = (*line_length).max(self.cursor.col);
        }
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
        if byte == b'\t' {
            self.put_tab();
            return;
        }

        self.put_raw_byte(byte);
    }

    fn put_tab(&mut self) {
        let mut count = 0;
        while count < VGA_TEXT_TAB_SPACES {
            self.put_raw_byte(VGA_TEXT_BLANK_BYTE);
            count += 1;
        }
    }

    fn put_raw_byte(&mut self, byte: u8) {
        let write_row = self.cursor.row;
        let write_col = self.cursor.col;
        let result = self.cursor.put_byte(byte);
        if let Some(cell_index) = result.cell_index {
            unsafe {
                *self.history.get_unchecked_mut(cell_index) = vga_text_cell(self.color, byte);
                let line_length = self.line_lengths.get_unchecked_mut(write_row);
                *line_length = (*line_length).max(write_col + 1);
            }
        } else {
            unsafe {
                let line_length = self.line_lengths.get_unchecked_mut(write_row);
                *line_length = (*line_length).max(write_col);
            }
        }
        if result.scrolled {
            // The cursor already hit the logical bottom, so keep the history as a
            // fixed-size ring-like window by shifting rows up and blanking the tail.
            vga_text_scroll_rows_up(
                &mut self.history,
                VGA_TEXT_DIMENSIONS.width(),
                VGA_TEXT_HISTORY_ROWS,
                vga_text_cell(self.color, VGA_TEXT_BLANK_BYTE),
            );
            vga_text_scroll_rows_up(&mut self.line_lengths, 1, VGA_TEXT_HISTORY_ROWS, 0);
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
        let cell_index = if let Some(index) = self.cursor.backspace_cell() {
            let row = self.cursor.row;
            unsafe {
                *self.line_lengths.get_unchecked_mut(row) = self.cursor.col;
            }
            Some(index)
        } else {
            self.backspace_previous_line_end(width)
        };

        if let Some(index) = cell_index {
            unsafe {
                *self.history.get_unchecked_mut(index) =
                    vga_text_cell(self.color, VGA_TEXT_BLANK_BYTE);
            }
        }
        self.viewport_top = vga_text_tail_viewport_top(self.cursor.row);
    }

    fn backspace_previous_line_end(&mut self, width: usize) -> Option<usize> {
        // If we are at column 0, backspace means "jump to the previous line's last
        // written character", not "do nothing".
        if self.cursor.row == 0 || width == 0 {
            return None;
        }

        let previous_row = self.cursor.row - 1;
        let previous_len = unsafe { *self.line_lengths.get_unchecked(previous_row) }.min(width);
        self.cursor.row = previous_row;

        if previous_len == 0 {
            self.cursor.col = 0;
            return None;
        }

        self.cursor.col = previous_len - 1;
        unsafe {
            *self.line_lengths.get_unchecked_mut(previous_row) = previous_len - 1;
        }
        Some((previous_row * width) + self.cursor.col)
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

    fn fill_line_lengths(&mut self, value: usize) {
        let mut idx = 0;
        while idx < self.line_lengths.len() {
            unsafe {
                *self.line_lengths.get_unchecked_mut(idx) = value;
            }
            idx += 1;
        }
    }
}

// The bank holds all terminal states plus the active-order list.
// `terminals` stores every slot, while `active_slots` says which ones are currently
// in play and in what order the user sees them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VgaTerminalBank {
    pub active_index: usize,
    pub active_count: usize,
    // This maps "visible terminal number" to "backing slot in `terminals`".
    // Only the first `active_count` entries matter.
    //
    // Example:
    // `active_slots[4] = 3` means "the 5th visible terminal is stored in
    // `terminals[3]`".
    pub active_slots: [usize; VGA_TEXT_TERMINAL_COUNT],
    pub terminals: [VgaTerminal; VGA_TEXT_TERMINAL_COUNT],
}

impl VgaTerminalBank {
    pub const fn new() -> Self {
        const EMPTY_TERMINAL: VgaTerminal = VgaTerminal::new();
        Self {
            active_index: 0,
            active_count: 1,
            // Start with a simple identity mapping. Later create/destroy operations
            // can reshuffle the visible order without moving the terminal storage.
            // No need to move a whole term buffer, just shift a few int within active_slots when deleting.
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
        // New terminals become active immediately, like opening a fresh tab.
        self.active_index = self.active_count;
        self.active_count += 1;
        true
    }

    pub fn destroy_active_terminal(&mut self) -> bool {
        if self.active_count <= 1 {
            // There is always at least one terminal alive.
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
        // If we deleted the last visible entry, move focus onto the new tail.
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

pub const fn terminal_label_color(index: usize) -> ColorCode {
    // Keep backgrounds in the low VGA range so the attribute high bit never turns into blink.
    let label_index = if index >= VGA_TEXT_TERMINAL_COUNT {
        VGA_TEXT_TERMINAL_COUNT - 1
    } else {
        index
    };

    match label_index {
        0 => ColorCode::vga(VgaColor::Yellow.code(), VgaColor::Blue.code()),
        1 => ColorCode::vga(VgaColor::White.code(), VgaColor::Red.code()),
        2 => ColorCode::vga(VgaColor::Black.code(), VgaColor::LightGray.code()),
        3 => ColorCode::vga(VgaColor::White.code(), VgaColor::Green.code()),
        4 => ColorCode::vga(VgaColor::Yellow.code(), VgaColor::Magenta.code()),
        5 => ColorCode::vga(VgaColor::Black.code(), VgaColor::Cyan.code()),
        6 => ColorCode::vga(VgaColor::White.code(), VgaColor::Brown.code()),
        7 => ColorCode::vga(VgaColor::LightGreen.code(), VgaColor::Black.code()),
        8 => ColorCode::vga(VgaColor::LightRed.code(), VgaColor::Blue.code()),
        9 => ColorCode::vga(VgaColor::LightCyan.code(), VgaColor::Red.code()),
        10 => ColorCode::vga(VgaColor::Black.code(), VgaColor::Green.code()),
        _ => ColorCode::vga(VgaColor::LightMagenta.code(), VgaColor::Black.code()),
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

// Convert the active terminal's short label into VGA cells so the writer can stamp it
// into the top-right corner during redraw.
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

// Pack one ASCII byte and one VGA color attribute into the 16-bit cell format that
// the text-mode framebuffer expects.
pub fn vga_text_cell<C: Into<ColorCode>>(color: C, byte: u8) -> u16 {
    let color = color.into();
    ((color.as_u8() as u16) << 8) | (byte as u16)
}

// Old helper APIs use a flat cursor index instead of row/col coordinates, so clamp
// anything out of bounds back to the safe starting cell.
pub fn vga_text_normalize_cursor(cursor: usize, cell_count: usize) -> usize {
    if cell_count == 0 || cursor >= cell_count {
        return 0;
    }

    cursor
}

// Write raw bytes into a flat VGA-style cell buffer, wrapping back to the front when
// the cursor reaches the end.
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

// Clamp a row/col cursor into the visible bounds of a screen.
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

// Generic "write bytes into a 2D text screen" helper used by tests and formatting code.
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

// Shift a row-oriented buffer up by one row and blank the new last row.
// This is shared by text history and line-length metadata so both stay in sync.
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

// Copy one viewport-sized slice out of a taller history buffer into a screen-sized buffer.
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

// Take a logical screen and place it inside the fixed physical VGA area.
// If the logical layout is smaller than 80x25, this centers it and blanks the rest.
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

// Move to the next line, scrolling the visible screen buffer if we were already on the last row.
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

// Public API surface: the rest of the kernel talks to `vga_text`, not directly to the
// hardware-facing writer module.
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
