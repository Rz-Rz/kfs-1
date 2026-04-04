use kfs::kernel::drivers::keyboard::{
    decode_scancode, direct_function_shortcut, process_shortcut_key, route_key_event,
    route_key_event_with_prefix, shortcut_terminal_index, KeyCode, KeyEvent, KeyboardRoute,
    KeyboardShortcut,
    KeyboardShortcutDecision, KeyboardShortcutState, KeyboardState,
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

fn apply_scancode_sequence(scancodes: &[u8]) -> Vec<String> {
    let mut keyboard_state = KeyboardState::new();
    let mut shortcut_state = KeyboardShortcutState::new();
    let mut log = Vec::new();

    for &scancode in scancodes {
        let Some(event) = decode_scancode(&mut keyboard_state, scancode) else {
            continue;
        };

        match process_shortcut_key(&mut shortcut_state, event) {
            KeyboardShortcutDecision::PassThrough => {
                log.extend(apply_route(route_key_event(event)));
            }
            KeyboardShortcutDecision::Consume => log.push("consume".to_string()),
            KeyboardShortcutDecision::Shortcut(shortcut) => {
                log.push(format!("command:{shortcut:?}"));
            }
        }
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
    let route = route_key_event(KeyEvent {
        code: KeyCode::Function(1),
        pressed: true,
        ctrl: false,
        shift: false,
        alt: true,
    });
    assert_eq!(apply_route(route), vec!["shortcut:alt-f1"]);
}

#[test]
fn bare_function_keys_select_terminals_without_echoing_text() {
    let route = route_key_event(KeyEvent {
        code: KeyCode::Function(3),
        pressed: true,
        ctrl: false,
        shift: false,
        alt: false,
    });
    assert_eq!(apply_route(route), vec!["shortcut:select-terminal:2"]);
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
    assert_eq!(shortcut_terminal_index(KeyboardShortcut::AltFunction(1)), Some(0));
    assert_eq!(shortcut_terminal_index(KeyboardShortcut::AltFunction(2)), Some(1));
    assert_eq!(shortcut_terminal_index(KeyboardShortcut::AltFunction(12)), Some(11));
    assert_eq!(shortcut_terminal_index(KeyboardShortcut::SelectTerminal(2)), Some(2));
    assert_eq!(shortcut_terminal_index(KeyboardShortcut::CreateTerminal), None);
}

#[test]
fn direct_function_shortcuts_cover_select_create_and_destroy() {
    assert_eq!(direct_function_shortcut(1), Some(KeyboardShortcut::SelectTerminal(0)));
    assert_eq!(direct_function_shortcut(10), Some(KeyboardShortcut::SelectTerminal(9)));
    assert_eq!(direct_function_shortcut(11), Some(KeyboardShortcut::CreateTerminal));
    assert_eq!(direct_function_shortcut(12), Some(KeyboardShortcut::DestroyTerminal));
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

#[test]
fn alt_a_prefix_consumes_the_trigger_key_without_echoing() {
    let mut state = KeyboardShortcutState::new();
    let decision = process_shortcut_key(
        &mut state,
        KeyEvent {
            code: KeyCode::Printable(b'a'),
            pressed: true,
            ctrl: false,
            shift: false,
            alt: true,
        },
    );

    assert_eq!(decision, KeyboardShortcutDecision::Consume);
    assert!(state.prefix_pending);
}

#[test]
fn alt_a_prefix_followed_by_c_creates_a_terminal() {
    let mut state = KeyboardShortcutState::new();

    assert_eq!(
        process_shortcut_key(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'a'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: true,
            },
        ),
        KeyboardShortcutDecision::Consume
    );

    assert_eq!(
        process_shortcut_key(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'c'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: false,
            },
        ),
        KeyboardShortcutDecision::Shortcut(KeyboardShortcut::CreateTerminal)
    );
    assert!(!state.prefix_pending);
}

#[test]
fn alt_a_prefix_followed_by_x_destroys_the_current_terminal() {
    let mut state = KeyboardShortcutState::new();

    assert_eq!(
        process_shortcut_key(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'a'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: true,
            },
        ),
        KeyboardShortcutDecision::Consume
    );

    assert_eq!(
        process_shortcut_key(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'x'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: false,
            },
        ),
        KeyboardShortcutDecision::Shortcut(KeyboardShortcut::DestroyTerminal)
    );
}

#[test]
fn alt_a_prefix_followed_by_a_digit_selects_that_terminal_number() {
    let mut state = KeyboardShortcutState::new();

    assert_eq!(
        process_shortcut_key(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'a'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: true,
            },
        ),
        KeyboardShortcutDecision::Consume
    );

    assert_eq!(
        process_shortcut_key(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'3'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: false,
            },
        ),
        KeyboardShortcutDecision::Shortcut(KeyboardShortcut::SelectTerminal(3))
    );
}

#[test]
fn alt_a_prefix_followed_by_zero_selects_the_first_terminal() {
    let mut state = KeyboardShortcutState::new();

    assert_eq!(
        process_shortcut_key(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'a'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: true,
            },
        ),
        KeyboardShortcutDecision::Consume
    );

    assert_eq!(
        process_shortcut_key(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'0'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: false,
            },
        ),
        KeyboardShortcutDecision::Shortcut(KeyboardShortcut::SelectTerminal(0))
    );
}

#[test]
fn alt_a_repeat_does_not_cancel_the_pending_terminal_command() {
    let log = apply_scancode_sequence(&[
        0x38, // left alt down
        0x1e, // a down -> arms the prefix
        0x1e, // repeated a down while still held
        0x9e, // a up
        0xb8, // alt up
        0x2e, // c down -> should still create a terminal
    ]);

    assert!(log.iter().all(|entry| entry != "put:99"));
    assert!(log.contains(&"command:CreateTerminal".to_string()));
}

#[test]
fn runtime_prefix_router_maps_alt_a_then_c_to_create_terminal() {
    let mut state = KeyboardShortcutState::new();

    assert_eq!(
        route_key_event_with_prefix(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'a'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: true,
            },
        ),
        KeyboardRoute::None
    );

    assert_eq!(
        route_key_event_with_prefix(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'c'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: false,
            },
        ),
        KeyboardRoute::Shortcut(KeyboardShortcut::CreateTerminal)
    );
}

#[test]
fn runtime_prefix_router_maps_alt_a_then_digit_to_select_terminal() {
    let mut state = KeyboardShortcutState::new();

    assert_eq!(
        route_key_event_with_prefix(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'a'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: true,
            },
        ),
        KeyboardRoute::None
    );

    assert_eq!(
        route_key_event_with_prefix(
            &mut state,
            KeyEvent {
                code: KeyCode::Printable(b'2'),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: false,
            },
        ),
        KeyboardRoute::Shortcut(KeyboardShortcut::SelectTerminal(2))
    );
}

#[test]
fn runtime_prefix_router_leaves_bare_f11_on_direct_shortcut_path() {
    let mut state = KeyboardShortcutState::new();

    assert_eq!(
        route_key_event_with_prefix(
            &mut state,
            KeyEvent {
                code: KeyCode::Function(11),
                pressed: true,
                ctrl: false,
                shift: false,
                alt: false,
            },
        ),
        KeyboardRoute::Shortcut(KeyboardShortcut::CreateTerminal)
    );
}
