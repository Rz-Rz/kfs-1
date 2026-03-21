use kfs::kernel::drivers::keyboard::{
    route_key_event, KeyCode, KeyEvent, KeyboardRoute, KeyboardShortcut,
};

fn apply_route(route: KeyboardRoute) -> Vec<String> {
    let mut log = Vec::new();
    match route {
        KeyboardRoute::PutByte(byte) => log.push(format!("put:{byte}")),
        KeyboardRoute::Backspace => log.push("backspace".to_string()),
        KeyboardRoute::ViewportUp => log.push("viewport-up".to_string()),
        KeyboardRoute::ViewportDown => log.push("viewport-down".to_string()),
        KeyboardRoute::Shortcut(KeyboardShortcut::AltFunction(index)) => {
            log.push(format!("shortcut:alt-f{index}"))
        }
        KeyboardRoute::None => log.push("none".to_string()),
    }
    log
}

#[test]
fn printable_input_routes_to_screen_byte_output() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Printable(b'x'),
        pressed: true,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["put:120"]);
}

#[test]
fn enter_routes_to_the_shared_newline_path() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Enter,
        pressed: true,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["put:10"]);
}

#[test]
fn backspace_routes_to_the_erase_operation() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Backspace,
        pressed: true,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["backspace"]);
}

#[test]
fn up_arrow_routes_to_history_viewport_movement() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::ArrowUp,
        pressed: true,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["viewport-up"]);
}

#[test]
fn down_arrow_routes_to_history_viewport_movement() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::ArrowDown,
        pressed: true,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["viewport-down"]);
}

#[test]
fn key_release_events_do_not_echo() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Printable(b'x'),
        pressed: false,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["none"]);
}

#[test]
fn alt_function_shortcuts_are_intercepted_instead_of_echoed() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Function(1),
        pressed: true,
        shift: false,
        alt: true,
    });
    assert_eq!(apply_route(route), vec!["shortcut:alt-f1"]);
}

#[test]
fn alt_modified_printable_input_does_not_leave_garbage_text() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Printable(b'a'),
        pressed: true,
        shift: false,
        alt: true,
    });
    assert_eq!(apply_route(route), vec!["none"]);
}
