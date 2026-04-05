use crate::kernel::klib::simd::{self, RuntimePolicy, ScalarBlockReason};
use crate::kernel::machine::cpu::{self, SimdDetection};
use crate::kernel::services::diagnostics;

pub(crate) fn initialize_runtime_policy(test_mode: bool) -> RuntimePolicy {
    let detection = cpu::detect_simd();
    let policy = policy_from_detection(detection);
    simd::install_runtime_policy(policy);
    if test_mode {
        emit_runtime_markers(policy);
    }
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

fn emit_runtime_markers(policy: RuntimePolicy) {
    diagnostics::write_line("SIMD_POLICY_OK");
    diagnostics::write_line("SIMD_MODE_SCALAR_ONLY");

    match policy.block_reason {
        ScalarBlockReason::NoCpuid => {
            diagnostics::write_line("SIMD_CPUID_ABSENT");
            diagnostics::write_line("SIMD_POLICY_NO_CPUID");
        }
        ScalarBlockReason::ForcedByPolicy => {
            diagnostics::write_line("SIMD_CPUID_PRESENT");
            diagnostics::write_line("SIMD_POLICY_FORCED_SCALAR");
        }
        ScalarBlockReason::RuntimeStateDisabled => {
            diagnostics::write_line("SIMD_CPUID_PRESENT");
            diagnostics::write_line("SIMD_POLICY_RUNTIME_BLOCKED");
        }
        ScalarBlockReason::Uninitialized => {}
    }
}
