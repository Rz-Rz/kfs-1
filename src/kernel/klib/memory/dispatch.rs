use crate::kernel::klib::simd::{RuntimePolicy, SimdFeature};

#[repr(u8)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum MemoryBackend {
    Scalar = 0,
    Sse2 = 1,
}

const HAS_SSE2_MEMCPY: bool = cfg!(any(target_arch = "x86", target_arch = "x86_64"));
const HAS_SSE2_MEMSET: bool = cfg!(any(target_arch = "x86", target_arch = "x86_64"));

pub const fn memcpy_backend(policy: RuntimePolicy) -> MemoryBackend {
    if HAS_SSE2_MEMCPY && policy.allows(SimdFeature::Sse2) {
        return MemoryBackend::Sse2;
    }

    MemoryBackend::Scalar
}

pub const fn memset_backend(policy: RuntimePolicy) -> MemoryBackend {
    if HAS_SSE2_MEMSET && policy.allows(SimdFeature::Sse2) {
        return MemoryBackend::Sse2;
    }

    MemoryBackend::Scalar
}
