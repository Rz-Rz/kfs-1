include!("../src/kernel/string/string_impl.rs");

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
fn strcmp_equal_strings() {
    let lhs = *b"42\0";
    let rhs = *b"42\0";
    let cmp = unsafe { strcmp(lhs.as_ptr(), rhs.as_ptr()) };
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
