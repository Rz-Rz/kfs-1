include!("../src/kernel/memory/memory_impl.rs");

#[test]
fn memcpy_basic_copy() {
    let src = [1u8, 2u8, 3u8, 4u8];
    let mut dst = [0u8; 4];
    unsafe {
        memcpy(dst.as_mut_ptr(), src.as_ptr(), src.len());
    }
    assert_eq!(dst, src);
}

#[test]
fn memcpy_zero_length_keeps_destination() {
    let src = [9u8, 8u8, 7u8];
    let mut dst = [1u8, 2u8, 3u8];
    unsafe {
        memcpy(dst.as_mut_ptr(), src.as_ptr(), 0);
    }
    assert_eq!(dst, [1u8, 2u8, 3u8]);
}

#[test]
fn memcpy_preserves_outside_range() {
    let src = [10u8, 11u8, 12u8];
    let mut dst = [0xAAu8, 0xBBu8, 0xCCu8, 0xDDu8, 0xEEu8];
    unsafe {
        memcpy(dst.as_mut_ptr().add(1), src.as_ptr(), src.len());
    }
    assert_eq!(dst, [0xAAu8, 10u8, 11u8, 12u8, 0xEEu8]);
}

#[test]
fn memcpy_allows_same_pointer() {
    let mut buf = [1u8, 2u8, 3u8, 4u8];
    let original = buf;
    let ptr = buf.as_mut_ptr();
    unsafe {
        memcpy(ptr, ptr as *const u8, buf.len());
    }
    assert_eq!(buf, original);
}

#[test]
fn memcpy_unaligned_pointers() {
    let src = [0u8, 5u8, 6u8, 7u8, 8u8];
    let mut dst = [0u8, 0u8, 0u8, 0u8, 0u8];
    unsafe {
        memcpy(dst.as_mut_ptr().add(1), src.as_ptr().add(1), 3);
    }
    assert_eq!(dst, [0u8, 5u8, 6u8, 7u8, 0u8]);
}

#[test]
fn memset_basic_fill() {
    let mut buf = [0u8; 6];
    unsafe {
        memset(buf.as_mut_ptr(), 0x2Au8, buf.len());
    }
    assert_eq!(buf, [0x2Au8; 6]);
}

#[test]
fn memset_zero_length_keeps_buffer() {
    let mut buf = [1u8, 2u8, 3u8];
    unsafe {
        memset(buf.as_mut_ptr(), 0xFFu8, 0);
    }
    assert_eq!(buf, [1u8, 2u8, 3u8]);
}

#[test]
fn memset_partial_range_preserves_edges() {
    let mut buf = [0x11u8, 0x22u8, 0x33u8, 0x44u8, 0x55u8];
    unsafe {
        memset(buf.as_mut_ptr().add(1), 0x99u8, 3);
    }
    assert_eq!(buf, [0x11u8, 0x99u8, 0x99u8, 0x99u8, 0x55u8]);
}
