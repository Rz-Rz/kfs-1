mod imp;

pub use self::imp::{
    decode_scancode, direct_function_shortcut, process_shortcut_key, route_key_event,
    route_key_event_with_prefix, shortcut_terminal_index, KeyCode, KeyEvent, KeyboardRoute,
    KeyboardShortcut, KeyboardShortcutDecision, KeyboardShortcutState, KeyboardState,
};

use self::imp::poll_scancode;

// The keyboard driver keeps just enough global state to decode a stream of
// scancodes across polls: modifier/extended-key state and the `Alt+A` prefix.
static mut KEYBOARD_STATE: KeyboardState = KeyboardState::new();
static mut KEYBOARD_SHORTCUT_STATE: KeyboardShortcutState = KeyboardShortcutState::new();

pub fn keyboard_init() {
    unsafe {
        KEYBOARD_STATE = KeyboardState::new();
        KEYBOARD_SHORTCUT_STATE = KeyboardShortcutState::new();
    }
}

// Poll one raw scancode byte, decode it into a key event, then run it through
// the prefix-shortcut logic and final console routing.
pub fn keyboard_poll_route() -> Option<KeyboardRoute> {
    let scancode = poll_scancode()?;

    unsafe {
        let state = &mut *core::ptr::addr_of_mut!(KEYBOARD_STATE);
        let shortcut_state = &mut *core::ptr::addr_of_mut!(KEYBOARD_SHORTCUT_STATE);

        decode_scancode(state, scancode)
            .map(|event| route_key_event_with_prefix(shortcut_state, event))
    }
}
