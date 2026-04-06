#[cfg(target_arch = "x86")]
use core::arch::x86 as simd;
#[cfg(target_arch = "x86_64")]
use core::arch::x86_64 as simd;

#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
#[inline(never)]
#[target_feature(enable = "sse2")]
pub(super) unsafe fn memset(dst: *mut u8, value: u8, mut len: usize) -> *mut u8 {
    if len == 0 {
        return dst;
    }

    let mut dst_ptr = dst;
    let pattern = simd::_mm_set1_epi8(value as i8);

    while len >= 16 {
        simd::_mm_storeu_si128(dst_ptr as *mut simd::__m128i, pattern);
        dst_ptr = dst_ptr.add(16);
        len -= 16;
    }

    while len > 0 {
        dst_ptr.write(value);
        dst_ptr = dst_ptr.add(1);
        len -= 1;
    }

    dst
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
#[inline(never)]
pub(super) unsafe fn memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    let mut idx: usize = 0;
    while idx < len {
        dst.add(idx).write(value);
        idx += 1;
    }

    dst
}
