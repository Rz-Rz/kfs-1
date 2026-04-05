use kfs::kernel::klib::memory::{memcpy, memcpy_backend, memset, memset_backend, MemoryBackend};
use kfs::kernel::klib::simd::{self, RuntimePolicy};

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
fn memcpy_returns_original_destination_pointer() {
    let src = [1u8, 2u8, 3u8];
    let mut dst = [0u8; 3];
    let expected = dst.as_mut_ptr();
    let returned = unsafe { memcpy(dst.as_mut_ptr(), src.as_ptr(), src.len()) };
    assert_eq!(returned, expected);
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
fn memset_zero_byte_fill() {
    let mut buf = [0x11u8, 0x22u8, 0x33u8, 0x44u8];
    unsafe {
        memset(buf.as_mut_ptr(), 0u8, buf.len());
    }
    assert_eq!(buf, [0u8; 4]);
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

#[test]
fn memset_returns_original_destination_pointer() {
    let mut buf = [0u8; 4];
    let expected = buf.as_mut_ptr();
    let returned = unsafe { memset(buf.as_mut_ptr(), 0xAA, buf.len()) };
    assert_eq!(returned, expected);
}

#[test]
fn memory_backends_default_to_scalar_when_policy_is_uninitialized() {
    simd::reset_runtime_policy();

    assert_eq!(memcpy_backend(), MemoryBackend::Scalar);
    assert_eq!(memset_backend(), MemoryBackend::Scalar);
}

#[test]
fn memory_backends_remain_scalar_when_runtime_is_owned_but_acceleration_is_deferred() {
    simd::install_runtime_policy(RuntimePolicy::acceleration_deferred(
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
    ));

    assert_eq!(memcpy_backend(), MemoryBackend::Scalar);
    assert_eq!(memset_backend(), MemoryBackend::Scalar);
}

#[test]
fn memory_backends_remain_scalar_when_policy_is_runtime_blocked() {
    simd::install_runtime_policy(RuntimePolicy::runtime_blocked(true, true, true, true));

    assert_eq!(memcpy_backend(), MemoryBackend::Scalar);
    assert_eq!(memset_backend(), MemoryBackend::Scalar);
}

#[test]
fn memory_backends_choose_sse2_when_policy_allows_it() {
    simd::install_runtime_policy(RuntimePolicy::acceleration_enabled(
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
    ));

    assert_eq!(memcpy_backend(), MemoryBackend::Sse2);
    assert_eq!(memset_backend(), MemoryBackend::Sse2);
}

#[test]
fn memcpy_sse2_backend_preserves_existing_contract() {
    simd::install_runtime_policy(RuntimePolicy::acceleration_enabled(
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
    ));

    let src = [0u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8, 16u8, 17u8, 18u8, 19u8, 20u8];
    let mut dst = [0xA5u8; 19];

    unsafe {
        memcpy(dst.as_mut_ptr().add(1), src.as_ptr().add(1), 16);
    }

    assert_eq!(
        dst,
        [0xA5u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8, 16u8, 17u8, 18u8, 19u8, 20u8, 0xA5u8, 0xA5u8]
    );
}

#[test]
fn memset_sse2_backend_preserves_existing_contract() {
    simd::install_runtime_policy(RuntimePolicy::acceleration_enabled(
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
    ));

    let mut buf = [0x11u8; 21];

    unsafe {
        memset(buf.as_mut_ptr().add(2), 0x77u8, 16);
    }

    assert_eq!(
        buf,
        [0x11u8, 0x11u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x77u8, 0x11u8, 0x11u8, 0x11u8]
    );
}
