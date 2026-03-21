use kfs::kernel::klib::string::{strcmp, strlen};

#[test]
fn strlen_empty_string() {
    let input = [0u8];
    let len = unsafe { strlen(input.as_ptr()) };
    assert_eq!(len, 0);
}

#[test]
fn strlen_regular_string() {
    let input = *b"kernel\0";
    let len = unsafe { strlen(input.as_ptr()) };
    assert_eq!(len, 6);
}

#[test]
fn strlen_embedded_nul_stops_at_first_terminator() {
    let input = [b'a', b'b', 0, b'c', 0];
    let len = unsafe { strlen(input.as_ptr()) };
    assert_eq!(len, 2);
}

#[test]
fn strlen_unaligned_start() {
    let input = [0xff, b'k', b'f', b's', 0];
    let len = unsafe { strlen(input.as_ptr().wrapping_add(1)) };
    assert_eq!(len, 3);
}

#[test]
fn strlen_crosses_natural_word_boundary() {
    let input = [b'a', b'b', b'c', b'd', b'e', b'f', b'g', b'h', b'i', 0];
    let len = unsafe { strlen(input.as_ptr()) };
    assert_eq!(len, 9);
}

#[test]
fn strcmp_equal_strings() {
    let lhs = *b"42\0";
    let rhs = *b"42\0";
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
    assert_eq!(cmp, 0);
}

#[test]
fn strcmp_same_pointer_is_equal() {
    let value = *b"kfs\0";
    let cmp = unsafe { strcmp(value.as_ptr(), value.as_ptr()) };
    assert_eq!(cmp, 0);
}

#[test]
fn strcmp_lexicographic_less() {
    let lhs = *b"abc\0";
    let rhs = *b"abd\0";
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
    assert!(cmp < 0);
}

#[test]
fn strcmp_lexicographic_greater() {
    let lhs = *b"abe\0";
    let rhs = *b"abd\0";
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
    assert!(cmp > 0);
}

#[test]
fn strcmp_prefix() {
    let lhs = *b"ab\0";
    let rhs = *b"abc\0";
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
    assert!(cmp < 0);
}

#[test]
fn strcmp_empty_vs_non_empty() {
    let lhs = [0u8];
    let rhs = *b"a\0";
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
    assert!(cmp < 0);
}

#[test]
fn strcmp_first_difference_in_middle_byte() {
    let lhs = *b"abxdef\0";
    let rhs = *b"abydef\0";
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
    assert!(cmp < 0);
}

#[test]
fn strcmp_high_byte_ordering_is_unsigned() {
    let lhs = [0x80, 0];
    let rhs = [0x7f, 0];
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
    assert!(cmp > 0);

    let lhs = [0xff, 0];
    let rhs = [0x00, 0];
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
    assert!(cmp > 0);
}
