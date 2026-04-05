use crate::kernel::klib::simd::{self, RuntimePolicy, ScalarBlockReason, SimdExecutionMode};
use crate::kernel::machine::cpu::{self, SimdDetection};
use crate::kernel::services::diagnostics;

pub(crate) fn initialize_runtime_policy(
    force_no_cpuid: bool,
    force_disable_simd: bool,
    test_mode: bool,
) -> RuntimePolicy {
    let detection = cpu::detect_simd();
    let policy = policy_from_detection(detection, force_no_cpuid, force_disable_simd);
    simd::install_runtime_policy(policy);
    if test_mode {
        emit_runtime_markers(policy);
    }
    policy
}

pub(crate) fn policy_from_detection(
    detection: SimdDetection,
    force_no_cpuid: bool,
    force_disable_simd: bool,
) -> RuntimePolicy {
    if force_no_cpuid {
        return RuntimePolicy::no_cpuid();
    }

    RuntimePolicy::phase2(
        detection.cpuid_supported,
        detection.forced_scalar || force_disable_simd,
        detection.mmx,
        detection.sse,
        detection.sse2,
    )
}

fn emit_runtime_markers(policy: RuntimePolicy) {
    diagnostics::write_line("SIMD_POLICY_OK");

    match policy.mode() {
        SimdExecutionMode::Uninitialized => diagnostics::write_line("SIMD_MODE_UNINITIALIZED"),
        SimdExecutionMode::ScalarOnly => diagnostics::write_line("SIMD_MODE_SCALAR_ONLY"),
    }

    if policy.has_cpuid() {
        diagnostics::write_line("SIMD_CPUID_PRESENT");
    } else {
        diagnostics::write_line("SIMD_CPUID_ABSENT");
    }

    if policy.mmx_detected {
        diagnostics::write_line("SIMD_MMX_OK");
    } else {
        diagnostics::write_line("SIMD_MMX_ABSENT");
    }

    if policy.sse_detected {
        diagnostics::write_line("SIMD_SSE_OK");
    } else {
        diagnostics::write_line("SIMD_SSE_ABSENT");
    }

    if policy.sse2_detected {
        diagnostics::write_line("SIMD_SSE2_OK");
    } else {
        diagnostics::write_line("SIMD_SSE2_ABSENT");
    }

    match policy.block_reason {
        ScalarBlockReason::Uninitialized => diagnostics::write_line("SIMD_POLICY_UNINITIALIZED"),
        ScalarBlockReason::NoCpuid => diagnostics::write_line("SIMD_POLICY_NO_CPUID"),
        ScalarBlockReason::NoSupportedFeatures => {
            diagnostics::write_line("SIMD_POLICY_NO_SUPPORTED_FEATURES")
        }
        ScalarBlockReason::ForcedByPolicy => diagnostics::write_line("SIMD_POLICY_FORCED_SCALAR"),
        ScalarBlockReason::RuntimeStateDisabled => {
            diagnostics::write_line("SIMD_POLICY_RUNTIME_BLOCKED")
        }
    }
}
