mod imp;

pub use imp::{
    decode_scancode, route_key_event, KeyCode, KeyEvent, KeyboardRoute, KeyboardShortcut,
    KeyboardState,
};

use imp::poll_scancode;

static mut KEYBOARD_STATE: KeyboardState = KeyboardState::new();

pub fn keyboard_init() {
    unsafe {
        KEYBOARD_STATE = KeyboardState::new();
    }
}

pub fn keyboard_poll_route() -> Option<KeyboardRoute> {
    let scancode = poll_scancode()?;

    unsafe {
        let state = &mut *core::ptr::addr_of_mut!(KEYBOARD_STATE);
        decode_scancode(state, scancode).map(route_key_event)
    }
}
