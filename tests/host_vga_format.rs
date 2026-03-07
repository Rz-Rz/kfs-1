include!("../src/kernel/vga/vga_format_impl.rs");

fn render_to_vec(format: &[u8], args: &[usize]) -> Vec<u8> {
    let mut output = Vec::new();
    render_printf_with_args(format.as_ptr(), args.as_ptr(), args.len(), |byte| output.push(byte));
    output
}

#[test]
fn decimal_zero_renders_as_single_zero() {
    let mut buffer = [0u8; MAX_USIZE_DECIMAL_DIGITS];
    let rendered = format_usize_decimal(0, &mut buffer);
    assert_eq!(rendered, b"0");
}

#[test]
fn decimal_regular_value_renders_all_digits() {
    let mut buffer = [0u8; MAX_USIZE_DECIMAL_DIGITS];
    let rendered = format_usize_decimal(12345, &mut buffer);
    assert_eq!(rendered, b"12345");
}

#[test]
fn decimal_max_usize_matches_std_formatting() {
    let mut buffer = [0u8; MAX_USIZE_DECIMAL_DIGITS];
    let rendered = format_usize_decimal(usize::MAX, &mut buffer);
    let expected = usize::MAX.to_string();
    assert_eq!(rendered, expected.as_bytes());
}

#[test]
fn hex_max_usize_matches_std_formatting() {
    let mut buffer = [0u8; MAX_USIZE_HEX_DIGITS];
    let rendered = format_usize_hex(usize::MAX, &mut buffer);
    let expected = format!("{:x}", usize::MAX);
    assert_eq!(rendered, expected.as_bytes());
}

#[test]
fn signed_min_value_matches_std_formatting() {
    let mut buffer = [0u8; MAX_ISIZE_DECIMAL_DIGITS];
    let rendered = format_isize_decimal(isize::MIN, &mut buffer);
    let expected = isize::MIN.to_string();
    assert_eq!(rendered, expected.as_bytes());
}

#[test]
fn printf_renders_unsigned_decimal() {
    let output = render_to_vec(b"line %u\n\0", &[7]);
    assert_eq!(output, b"line 7\n");
}

#[test]
fn printf_renders_percent_escape() {
    let output = render_to_vec(b"done 100%%\0", &[]);
    assert_eq!(output, b"done 100%");
}

#[test]
fn printf_renders_signed_decimal() {
    let output = render_to_vec(b"value=%d\0", &[(-42isize) as usize]);
    assert_eq!(output, b"value=-42");
}

#[test]
fn printf_renders_hex_char_and_c_string() {
    let hello = b"hello\0";
    let output = render_to_vec(
        b"%x %c %s\0",
        &[0x2ausize, b'Z' as usize, hello.as_ptr() as usize],
    );
    assert_eq!(output, b"2a Z hello");
}

#[test]
fn printf_marks_missing_arguments() {
    let output = render_to_vec(b"a=%u b=%u\0", &[1usize]);
    assert_eq!(output, b"a=1 b=<arg?>");
}

#[test]
fn printf_mixed_placeholders_render_in_order() {
    let world = b"world\0";
    let output = render_to_vec(
        b"u=%u d=%d x=%x c=%c s=%s %%\0",
        &[15usize, (-9isize) as usize, 0x2ausize, b'Q' as usize, world.as_ptr() as usize],
    );
    assert_eq!(output, b"u=15 d=-9 x=2a c=Q s=world %");
}

#[test]
fn printf_null_string_pointer_renders_marker() {
    let output = render_to_vec(b"name=%s\0", &[0usize]);
    assert_eq!(output, b"name=(null)");
}

#[test]
fn printf_unknown_specifier_is_left_visible() {
    let output = render_to_vec(b"bad=%q\0", &[77usize]);
    assert_eq!(output, b"bad=%q");
}

#[test]
fn printf_trailing_percent_keeps_literal_percent() {
    let output = render_to_vec(b"cut here %\0", &[]);
    assert_eq!(output, b"cut here %");
}

#[test]
fn printf_ignores_extra_arguments() {
    let output = render_to_vec(b"only %u\0", &[1usize, 2usize, 3usize]);
    assert_eq!(output, b"only 1");
}

#[test]
fn printf_char_uses_low_byte_of_argument() {
    let output = render_to_vec(b"%c\0", &[0x1041usize]);
    assert_eq!(output, b"A");
}
