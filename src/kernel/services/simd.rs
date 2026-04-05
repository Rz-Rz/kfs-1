use crate::kernel::klib::simd::{self, RuntimePolicy};
use crate::kernel::machine::cpu::{self, SimdDetection};

pub(crate) fn initialize_runtime_policy() -> RuntimePolicy {
    let detection = cpu::detect_simd();
    let policy = policy_from_detection(detection);
    simd::install_runtime_policy(policy);
    policy
}

pub(crate) fn policy_from_detection(detection: SimdDetection) -> RuntimePolicy {
    if !detection.cpuid_supported {
        return RuntimePolicy::no_cpuid();
    }

    if detection.forced_scalar {
        return RuntimePolicy::forced_scalar();
    }

    RuntimePolicy::runtime_blocked(detection.mmx, detection.sse, detection.sse2)
}
