use crate::kernel::machine::port::Port;

const PS2_DATA_PORT: Port = Port::new(0x60);
const PS2_STATUS_PORT: Port = Port::new(0x64);
const PS2_OUTPUT_FULL_MASK: u8 = 0x01;

// This is the decoded meaning of one key after we translate the raw scancode.
// It is still low-level on purpose: routing text and shortcuts happens later.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyCode {
    Printable(u8),
    Enter,
    Backspace,
    Tab,
    ArrowUp,
    ArrowDown,
    CtrlLeft,
    CtrlRight,
    ShiftLeft,
    ShiftRight,
    AltLeft,
    AltRight,
    Function(u8),
    Unknown,
}

// A decoded key transition plus a snapshot of the modifier state at that moment.
// Carrying the modifier bits on every event keeps the routing code simple.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KeyEvent {
    pub code: KeyCode,
    pub pressed: bool,
    pub ctrl: bool,
    pub shift: bool,
    pub alt: bool,
}

// This is the small amount of state we need while decoding a PS/2 byte stream:
// which modifiers are currently held, and whether the last byte was the `0xE0`
// prefix used by extended keys like arrows and right-side modifiers.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KeyboardState {
    pub ctrl: bool,
    pub shift: bool,
    pub alt: bool,
    extended_prefix: bool,
}

impl KeyboardState {
    pub const fn new() -> Self {
        Self {
            ctrl: false,
            shift: false,
            alt: false,
            extended_prefix: false,
        }
    }
}

// Higher-level keyboard commands understood by the console layer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyboardShortcut {
    AltFunction(u8),
    CreateTerminal,
    DestroyTerminal,
    SelectTerminal(usize),
}

/// Turn a terminal-related shortcut into the terminal index it refers to.
///
/// Keeping this mapping here means terminal-selection policy can change without
/// touching the lower-level scancode decoder.
pub fn shortcut_terminal_index(shortcut: KeyboardShortcut) -> Option<usize> {
    match shortcut {
        // match values from 1 to 12 & store the matched value in index
        KeyboardShortcut::AltFunction(index @ 1..=12) => Some((index - 1) as usize),
        KeyboardShortcut::SelectTerminal(index) => Some(index),
        KeyboardShortcut::CreateTerminal | KeyboardShortcut::DestroyTerminal => None,
        KeyboardShortcut::AltFunction(_) => None,
    }
}

/// Map bare function keys onto terminal commands.
///
/// Plain `F1..F12` are handy in QEMU because host shortcuts are less likely to
/// steal them than `Alt+letter` combos.
pub fn direct_function_shortcut(index: u8) -> Option<KeyboardShortcut> {
    match index {
        1..=10 => Some(KeyboardShortcut::SelectTerminal((index - 1) as usize)),
        11 => Some(KeyboardShortcut::CreateTerminal),
        12 => Some(KeyboardShortcut::DestroyTerminal),
        _ => None,
    }
}

// Final action for the console loop after decoding and shortcut handling.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyboardRoute {
    PutByte(u8),
    Backspace,
    ViewportUp,
    ViewportDown,
    Shortcut(KeyboardShortcut),
    None,
}

fn has_pending_scancode() -> bool {
    let status = unsafe { PS2_STATUS_PORT.read_u8() };
    (status & PS2_OUTPUT_FULL_MASK) != 0
}

// Read one byte from the PS/2 controller if it has something waiting.
pub(super) fn poll_scancode() -> Option<u8> {
    if !has_pending_scancode() {
        return None;
    }

    Some(unsafe { PS2_DATA_PORT.read_u8() })
}

// Translate the printable subset of set-1 scancodes into ASCII.
// Non-printable keys are handled elsewhere in the decoder.
fn ascii_for_scancode(scancode: u8, shift: bool) -> Option<u8> {
    let byte = match (scancode, shift) {
        (0x02, false) => b'1',
        (0x03, false) => b'2',
        (0x04, false) => b'3',
        (0x05, false) => b'4',
        (0x06, false) => b'5',
        (0x07, false) => b'6',
        (0x08, false) => b'7',
        (0x09, false) => b'8',
        (0x0A, false) => b'9',
        (0x0B, false) => b'0',
        (0x0C, false) => b'-',
        (0x0D, false) => b'=',
        (0x10, false) => b'q',
        (0x11, false) => b'w',
        (0x12, false) => b'e',
        (0x13, false) => b'r',
        (0x14, false) => b't',
        (0x15, false) => b'y',
        (0x16, false) => b'u',
        (0x17, false) => b'i',
        (0x18, false) => b'o',
        (0x19, false) => b'p',
        (0x1A, false) => b'[',
        (0x1B, false) => b']',
        (0x1E, false) => b'a',
        (0x1F, false) => b's',
        (0x20, false) => b'd',
        (0x21, false) => b'f',
        (0x22, false) => b'g',
        (0x23, false) => b'h',
        (0x24, false) => b'j',
        (0x25, false) => b'k',
        (0x26, false) => b'l',
        (0x27, false) => b';',
        (0x28, false) => b'\'',
        (0x29, false) => b'`',
        (0x2B, false) => b'\\',
        (0x2C, false) => b'z',
        (0x2D, false) => b'x',
        (0x2E, false) => b'c',
        (0x2F, false) => b'v',
        (0x30, false) => b'b',
        (0x31, false) => b'n',
        (0x32, false) => b'm',
        (0x33, false) => b',',
        (0x34, false) => b'.',
        (0x35, false) => b'/',
        (0x39, false) => b' ',
        (0x02, true) => b'!',
        (0x03, true) => b'@',
        (0x04, true) => b'#',
        (0x05, true) => b'$',
        (0x06, true) => b'%',
        (0x07, true) => b'^',
        (0x08, true) => b'&',
        (0x09, true) => b'*',
        (0x0A, true) => b'(',
        (0x0B, true) => b')',
        (0x0C, true) => b'_',
        (0x0D, true) => b'+',
        (0x10, true) => b'Q',
        (0x11, true) => b'W',
        (0x12, true) => b'E',
        (0x13, true) => b'R',
        (0x14, true) => b'T',
        (0x15, true) => b'Y',
        (0x16, true) => b'U',
        (0x17, true) => b'I',
        (0x18, true) => b'O',
        (0x19, true) => b'P',
        (0x1A, true) => b'{',
        (0x1B, true) => b'}',
        (0x1E, true) => b'A',
        (0x1F, true) => b'S',
        (0x20, true) => b'D',
        (0x21, true) => b'F',
        (0x22, true) => b'G',
        (0x23, true) => b'H',
        (0x24, true) => b'J',
        (0x25, true) => b'K',
        (0x26, true) => b'L',
        (0x27, true) => b':',
        (0x28, true) => b'"',
        (0x29, true) => b'~',
        (0x2B, true) => b'|',
        (0x2C, true) => b'Z',
        (0x2D, true) => b'X',
        (0x2E, true) => b'C',
        (0x2F, true) => b'V',
        (0x30, true) => b'B',
        (0x31, true) => b'N',
        (0x32, true) => b'M',
        (0x33, true) => b'<',
        (0x34, true) => b'>',
        (0x35, true) => b'?',
        (0x39, true) => b' ',
        _ => return None,
    };

    Some(byte)
}

// `F1..F12` are split across two ranges in set-1 scancodes, so we normalize
// them here before the routing code looks at them.
fn function_key_number(scancode: u8) -> Option<u8> {
    match scancode {
        0x3B..=0x44 => Some((scancode - 0x3A) as u8),
        0x57 => Some(11),
        0x58 => Some(12),
        _ => None,
    }
}

// Turn one raw scancode byte into a `KeyEvent`.
//
// The important bits of the format are:
// - `0xE0` means "the next byte is an extended key",
// - bit 7 tells us whether this is a press or a release,
// - some keys also update the tracked modifier state on the way through.
pub fn decode_scancode(state: &mut KeyboardState, scancode: u8) -> Option<KeyEvent> {
    if scancode == 0xE0 {
        state.extended_prefix = true;
        return None;
    }

    let extended = state.extended_prefix;
    state.extended_prefix = false;

    let pressed = (scancode & 0x80) == 0;
    let base = scancode & 0x7f;

    let code = match (extended, base) {
        (false, 0x1D) => {
            state.ctrl = pressed;
            KeyCode::CtrlLeft
        }
        (true, 0x1D) => {
            state.ctrl = pressed;
            KeyCode::CtrlRight
        }
        (false, 0x2A) => {
            state.shift = pressed;
            KeyCode::ShiftLeft
        }
        (false, 0x36) => {
            state.shift = pressed;
            KeyCode::ShiftRight
        }
        (false, 0x38) => {
            state.alt = pressed;
            KeyCode::AltLeft
        }
        (true, 0x38) => {
            state.alt = pressed;
            KeyCode::AltRight
        }
        (true, 0x48) => KeyCode::ArrowUp,
        (true, 0x50) => KeyCode::ArrowDown,
        (_, 0x1C) => KeyCode::Enter,
        (_, 0x0E) => KeyCode::Backspace,
        (_, 0x0F) => KeyCode::Tab,
        (_, code) if function_key_number(code).is_some() => {
            KeyCode::Function(function_key_number(code).unwrap())
        }
        (false, code) => ascii_for_scancode(code, state.shift)
            .map(KeyCode::Printable)
            .unwrap_or(KeyCode::Unknown),
        (true, _) => KeyCode::Unknown,
    };

    Some(KeyEvent {
        code,
        pressed,
        ctrl: state.ctrl,
        shift: state.shift,
        alt: state.alt,
    })
}

// Route a decoded key into the small set of actions the console cares about.
// By this point we mostly only pass through plain text, navigation, and a few
// built-in shortcuts.
pub fn route_key_event(event: KeyEvent) -> KeyboardRoute {
    if !event.pressed {
        return KeyboardRoute::None;
    }

    match event.code {
        KeyCode::Printable(byte) if !event.alt && !event.ctrl => KeyboardRoute::PutByte(byte),
        KeyCode::Enter if !event.alt && !event.ctrl => KeyboardRoute::PutByte(b'\n'),
        KeyCode::Backspace if !event.alt && !event.ctrl => KeyboardRoute::Backspace,
        KeyCode::ArrowUp if !event.alt && !event.ctrl => KeyboardRoute::ViewportUp,
        KeyCode::ArrowDown if !event.alt && !event.ctrl => KeyboardRoute::ViewportDown,
        KeyCode::Tab if !event.alt && !event.ctrl => KeyboardRoute::PutByte(b'\t'),
        KeyCode::Function(index) if !event.alt && !event.ctrl && !event.shift => {
            direct_function_shortcut(index)
                .map(KeyboardRoute::Shortcut)
                .unwrap_or(KeyboardRoute::None)
        }
        KeyCode::Function(index) if event.alt => {
            KeyboardRoute::Shortcut(KeyboardShortcut::AltFunction(index))
        }
        _ => KeyboardRoute::None,
    }
}
