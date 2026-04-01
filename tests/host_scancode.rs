use kfs::kernel::drivers::keyboard::{
    decode_scancode, KeyCode, KeyEvent, KeyboardState,
};

#[test]
fn letter_key_press_maps_to_printable_ascii() {
    let mut state = KeyboardState::new();
    let event = decode_scancode(&mut state, 0x1e).expect("expected key event");
    assert_eq!(
        event,
        KeyEvent {
            code: KeyCode::Printable(b'a'),
            pressed: true,
            ctrl: false,
            shift: false,
            alt: false,
        }
    );
}

#[test]
fn shift_changes_letter_case_until_release() {
    let mut state = KeyboardState::new();

    let shift_press = decode_scancode(&mut state, 0x2a).expect("expected shift press");
    assert_eq!(shift_press.code, KeyCode::ShiftLeft);
    assert!(shift_press.pressed);
    assert!(state.shift);

    let shifted_a = decode_scancode(&mut state, 0x1e).expect("expected shifted key");
    assert_eq!(shifted_a.code, KeyCode::Printable(b'A'));
    assert!(shifted_a.shift);

    let shift_release = decode_scancode(&mut state, 0xaa).expect("expected shift release");
    assert_eq!(shift_release.code, KeyCode::ShiftLeft);
    assert!(!shift_release.pressed);
    assert!(!state.shift);

    let plain_a = decode_scancode(&mut state, 0x1e).expect("expected plain key");
    assert_eq!(plain_a.code, KeyCode::Printable(b'a'));
}

#[test]
fn enter_and_backspace_decode_as_control_keys() {
    let mut state = KeyboardState::new();
    let enter = decode_scancode(&mut state, 0x1c).expect("expected enter");
    let backspace = decode_scancode(&mut state, 0x0e).expect("expected backspace");

    assert_eq!(enter.code, KeyCode::Enter);
    assert_eq!(backspace.code, KeyCode::Backspace);
}

#[test]
fn alt_function_key_is_distinguishable_for_shortcuts() {
    let mut state = KeyboardState::new();

    let alt_press = decode_scancode(&mut state, 0x38).expect("expected alt press");
    assert_eq!(alt_press.code, KeyCode::AltLeft);
    assert!(state.alt);

    let function = decode_scancode(&mut state, 0x3b).expect("expected f1 press");
    assert_eq!(function.code, KeyCode::Function(1));
    assert!(function.alt);
}

#[test]
fn control_modifier_tracks_press_and_release() {
    let mut state = KeyboardState::new();

    let ctrl_press = decode_scancode(&mut state, 0x1d).expect("expected ctrl press");
    assert_eq!(ctrl_press.code, KeyCode::CtrlLeft);
    assert!(ctrl_press.pressed);
    assert!(ctrl_press.ctrl);
    assert!(state.ctrl);

    let controlled_a = decode_scancode(&mut state, 0x1e).expect("expected ctrl+a press");
    assert_eq!(controlled_a.code, KeyCode::Printable(b'a'));
    assert!(controlled_a.ctrl);

    let ctrl_release = decode_scancode(&mut state, 0x9d).expect("expected ctrl release");
    assert_eq!(ctrl_release.code, KeyCode::CtrlLeft);
    assert!(!ctrl_release.pressed);
    assert!(!state.ctrl);
}

#[test]
fn extended_right_alt_updates_modifier_state() {
    let mut state = KeyboardState::new();

    assert_eq!(decode_scancode(&mut state, 0xe0), None);
    let alt_press = decode_scancode(&mut state, 0x38).expect("expected right alt press");
    assert_eq!(alt_press.code, KeyCode::AltRight);
    assert!(state.alt);

    assert_eq!(decode_scancode(&mut state, 0xe0), None);
    let alt_release = decode_scancode(&mut state, 0xb8).expect("expected right alt release");
    assert_eq!(alt_release.code, KeyCode::AltRight);
    assert!(!alt_release.pressed);
    assert!(!state.alt);
}

#[test]
fn extended_up_arrow_decodes_as_a_navigation_key() {
    let mut state = KeyboardState::new();

    assert_eq!(decode_scancode(&mut state, 0xe0), None);
    let up = decode_scancode(&mut state, 0x48).expect("expected up-arrow press");
    assert_eq!(up.code, KeyCode::ArrowUp);
    assert!(up.pressed);
}

#[test]
fn extended_down_arrow_decodes_as_a_navigation_key() {
    let mut state = KeyboardState::new();

    assert_eq!(decode_scancode(&mut state, 0xe0), None);
    let down = decode_scancode(&mut state, 0x50).expect("expected down-arrow press");
    assert_eq!(down.code, KeyCode::ArrowDown);
    assert!(down.pressed);
}

#[test]
fn break_codes_become_release_events() {
    let mut state = KeyboardState::new();
    let release = decode_scancode(&mut state, 0x9e).expect("expected key release");
    assert_eq!(release.code, KeyCode::Printable(b'a'));
    assert!(!release.pressed);
}
