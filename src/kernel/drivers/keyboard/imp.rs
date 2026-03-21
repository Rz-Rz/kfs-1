use crate::kernel::machine::port::Port;

const PS2_DATA_PORT: Port = Port::new(0x60);
const PS2_STATUS_PORT: Port = Port::new(0x64);
const PS2_OUTPUT_FULL_MASK: u8 = 0x01;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyCode {
    Printable(u8),
    Enter,
    Backspace,
    Tab,
    ArrowUp,
    ArrowDown,
    ShiftLeft,
    ShiftRight,
    AltLeft,
    AltRight,
    Function(u8),
    Unknown,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KeyEvent {
    pub code: KeyCode,
    pub pressed: bool,
    pub shift: bool,
    pub alt: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KeyboardState {
    pub shift: bool,
    pub alt: bool,
    extended_prefix: bool,
}

impl KeyboardState {
    pub const fn new() -> Self {
        Self {
            shift: false,
            alt: false,
            extended_prefix: false,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyboardShortcut {
    AltFunction(u8),
}

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

pub(super) fn poll_scancode() -> Option<u8> {
    if !has_pending_scancode() {
        return None;
    }

    Some(unsafe { PS2_DATA_PORT.read_u8() })
}

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

fn function_key_number(scancode: u8) -> Option<u8> {
    match scancode {
        0x3B..=0x44 => Some((scancode - 0x3A) as u8),
        0x57 => Some(11),
        0x58 => Some(12),
        _ => None,
    }
}

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
        shift: state.shift,
        alt: state.alt,
    })
}

pub fn route_key_event(event: KeyEvent) -> KeyboardRoute {
    if !event.pressed {
        return KeyboardRoute::None;
    }

    match event.code {
        KeyCode::Printable(byte) if !event.alt => KeyboardRoute::PutByte(byte),
        KeyCode::Enter if !event.alt => KeyboardRoute::PutByte(b'\n'),
        KeyCode::Backspace if !event.alt => KeyboardRoute::Backspace,
        KeyCode::ArrowUp if !event.alt => KeyboardRoute::ViewportUp,
        KeyCode::ArrowDown if !event.alt => KeyboardRoute::ViewportDown,
        KeyCode::Tab if !event.alt => KeyboardRoute::PutByte(b'\t'),
        KeyCode::Function(index) if event.alt => {
            KeyboardRoute::Shortcut(KeyboardShortcut::AltFunction(index))
        }
        _ => KeyboardRoute::None,
    }
}
