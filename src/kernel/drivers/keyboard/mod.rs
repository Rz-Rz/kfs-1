mod imp;

pub use self::imp::{
    decode_scancode, direct_function_shortcut, process_shortcut_key, route_key_event,
    shortcut_terminal_index, KeyCode, KeyEvent, KeyboardRoute, KeyboardShortcut,
    KeyboardShortcutDecision, KeyboardShortcutState, KeyboardState,
};

use self::imp::poll_scancode;

static mut KEYBOARD_STATE: KeyboardState = KeyboardState::new();
static mut KEYBOARD_SHORTCUT_STATE: KeyboardShortcutState = KeyboardShortcutState::new();

pub fn keyboard_init() {
    unsafe {
        KEYBOARD_STATE = KeyboardState::new();
        KEYBOARD_SHORTCUT_STATE = KeyboardShortcutState::new();
    }
}

pub fn keyboard_poll_route() -> Option<KeyboardRoute> {
    let scancode = poll_scancode()?;

    unsafe {
        let state = &mut *core::ptr::addr_of_mut!(KEYBOARD_STATE);
        let shortcut_state = &mut *core::ptr::addr_of_mut!(KEYBOARD_SHORTCUT_STATE);

        decode_scancode(state, scancode).map(|event| match process_shortcut_key(shortcut_state, event) {
            KeyboardShortcutDecision::PassThrough => route_key_event(event),
            KeyboardShortcutDecision::Consume => KeyboardRoute::None,
            KeyboardShortcutDecision::Shortcut(shortcut) => KeyboardRoute::Shortcut(shortcut),
        })
    }
}
