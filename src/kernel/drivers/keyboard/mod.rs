mod imp;

pub use self::imp::{
    decode_scancode, direct_function_shortcut, route_key_event, shortcut_terminal_index, KeyCode,
    KeyEvent, KeyboardRoute, KeyboardShortcut, KeyboardState,
};

use self::imp::poll_scancode;

// The keyboard driver keeps just enough global state to decode a stream of
// scancodes across polls: modifier/extended-key state and the `Alt+A` prefix.
static mut KEYBOARD_STATE: KeyboardState = KeyboardState::new();

pub fn keyboard_init() {
    unsafe {
        KEYBOARD_STATE = KeyboardState::new();
    }
}

// Poll one raw scancode byte, decode it into a key event, then run it through
// the prefix-shortcut logic and final console routing.
pub fn keyboard_poll_route() -> Option<KeyboardRoute> {
    let scancode = poll_scancode()?;

    unsafe {
        let state = &mut *core::ptr::addr_of_mut!(KEYBOARD_STATE);
        decode_scancode(state, scancode).map(route_key_event)
    }
}
