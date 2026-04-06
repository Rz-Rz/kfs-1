use kfs::kernel::drivers::keyboard::{
    direct_function_shortcut, route_key_event, shortcut_terminal_index, KeyCode, KeyEvent,
    KeyboardRoute, KeyboardShortcut,
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
        KeyboardRoute::Shortcut(KeyboardShortcut::CreateTerminal) => {
            log.push("shortcut:create-terminal".to_string())
        }
        KeyboardRoute::Shortcut(KeyboardShortcut::DestroyTerminal) => {
            log.push("shortcut:destroy-terminal".to_string())
        }
        KeyboardRoute::Shortcut(KeyboardShortcut::SelectTerminal(index)) => {
            log.push(format!("shortcut:select-terminal:{index}"))
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
        ctrl: false,
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
        ctrl: false,
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
        ctrl: false,
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
        ctrl: false,
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
        ctrl: false,
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
        ctrl: false,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["none"]);
}

#[test]
fn alt_function_shortcuts_are_intercepted_instead_of_echoed() {
    for index in 1..=12 {
        let route = route_key_event(KeyEvent {
            code: KeyCode::Function(index),
            pressed: true,
            ctrl: false,
            shift: false,
            alt: true,
        });
        assert_eq!(apply_route(route), vec![format!("shortcut:alt-f{index}")]);
    }
}

#[test]
fn bare_function_keys_select_terminals_without_echoing_text() {
    for index in 1..=10 {
        let route = route_key_event(KeyEvent {
            code: KeyCode::Function(index),
            pressed: true,
            ctrl: false,
            shift: false,
            alt: false,
        });
        assert_eq!(
            apply_route(route),
            vec![format!("shortcut:select-terminal:{}", index - 1)]
        );
    }
}

#[test]
fn f11_creates_a_terminal_without_a_prefix_key() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Function(11),
        pressed: true,
        ctrl: false,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["shortcut:create-terminal"]);
}

#[test]
fn f12_destroys_the_current_terminal_without_a_prefix_key() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Function(12),
        pressed: true,
        ctrl: false,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["shortcut:destroy-terminal"]);
}

#[test]
fn shortcut_terminal_indices_cover_alt_functions_and_command_selectors() {
    for index in 1..=12 {
        assert_eq!(
            shortcut_terminal_index(KeyboardShortcut::AltFunction(index)),
            Some((index - 1) as usize)
        );
    }
    assert_eq!(
        shortcut_terminal_index(KeyboardShortcut::SelectTerminal(2)),
        Some(2)
    );
    assert_eq!(
        shortcut_terminal_index(KeyboardShortcut::CreateTerminal),
        None
    );
}

#[test]
fn direct_function_shortcuts_cover_select_create_and_destroy() {
    for index in 1..=10 {
        assert_eq!(
            direct_function_shortcut(index),
            Some(KeyboardShortcut::SelectTerminal((index - 1) as usize))
        );
    }
    assert_eq!(
        direct_function_shortcut(11),
        Some(KeyboardShortcut::CreateTerminal)
    );
    assert_eq!(
        direct_function_shortcut(12),
        Some(KeyboardShortcut::DestroyTerminal)
    );
    assert_eq!(direct_function_shortcut(0), None);
    assert_eq!(direct_function_shortcut(13), None);
}

#[test]
fn alt_modified_printable_input_does_not_leave_garbage_text() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Printable(b'a'),
        pressed: true,
        ctrl: false,
        shift: false,
        alt: true,
    });
    assert_eq!(apply_route(route), vec!["none"]);
}

#[test]
fn ctrl_modified_printable_input_does_not_echo_text() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Printable(b'a'),
        pressed: true,
        ctrl: true,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["none"]);
}
