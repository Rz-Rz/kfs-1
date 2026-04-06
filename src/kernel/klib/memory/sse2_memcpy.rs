#[cfg(target_arch = "x86")]
use core::arch::x86 as sse2;
#[cfg(target_arch = "x86_64")]
use core::arch::x86_64 as sse2;

#[inline(never)]
pub(super) unsafe fn memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    if len == 0 {
        return dst;
    }

    #[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
    unsafe {
        return memcpy_sse2(dst, src, len);
    }

    #[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
    unsafe {
        return memcpy_scalar(dst, src, len);
    }
}

#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
#[inline(never)]
#[target_feature(enable = "sse2")]
unsafe fn memcpy_sse2(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    let mut dst_ptr = dst;
    let mut src_ptr = src;
    let mut remaining = len;

    while remaining >= 16 {
        let value = sse2::_mm_loadu_si128(src_ptr.cast::<sse2::__m128i>());
        sse2::_mm_storeu_si128(dst_ptr.cast::<sse2::__m128i>(), value);
        dst_ptr = dst_ptr.add(16);
        src_ptr = src_ptr.add(16);
        remaining -= 16;
    }

    while remaining != 0 {
        dst_ptr.write(src_ptr.read());
        dst_ptr = dst_ptr.add(1);
        src_ptr = src_ptr.add(1);
        remaining -= 1;
    }

    dst
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
#[inline(never)]
unsafe fn memcpy_scalar(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    let mut idx = 0usize;
    while idx < len {
        unsafe {
            dst.add(idx).write(src.add(idx).read());
        }
        idx += 1;
    }
    dst
}
