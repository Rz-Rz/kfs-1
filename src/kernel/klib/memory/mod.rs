use crate::kernel::klib::simd::{self, RuntimePolicy, SimdExecutionMode, SimdFeature};

mod dispatch;
mod imp;
mod sse2_memcpy;
mod sse2_memset;

pub use self::dispatch::MemoryBackend;

#[no_mangle]
pub unsafe extern "C" fn kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    unsafe { memcpy(dst, src, len) }
}

#[no_mangle]
pub unsafe extern "C" fn kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    unsafe { memset(dst, value, len) }
}

pub unsafe fn memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
    match memcpy_backend() {
        MemoryBackend::Scalar => unsafe { imp::memcpy(dst, src, len) },
        MemoryBackend::Sse2 => unsafe { sse2_memcpy::memcpy(dst, src, len) },
    }
}

pub unsafe fn memset(dst: *mut u8, value: u8, len: usize) -> *mut u8 {
    match memset_backend() {
        MemoryBackend::Scalar => unsafe { imp::memset(dst, value, len) },
        MemoryBackend::Sse2 => unsafe { sse2_memset::memset(dst, value, len) },
    }
}

pub fn simd_policy() -> RuntimePolicy {
    simd::runtime_policy()
}

pub fn simd_mode() -> SimdExecutionMode {
    simd::simd_mode()
}

pub fn simd_acceleration_allowed(feature: SimdFeature) -> bool {
    simd::runtime_policy().allows(feature)
}

pub fn memcpy_backend() -> MemoryBackend {
    dispatch::memcpy_backend(simd::runtime_policy())
}

pub fn memset_backend() -> MemoryBackend {
    dispatch::memset_backend(simd::runtime_policy())
}
