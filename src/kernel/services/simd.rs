use crate::kernel::klib::simd::{
    self, RuntimePolicy, RuntimeStateSummary, ScalarBlockReason, SimdExecutionMode,
};
use crate::kernel::machine::cpu::{self, SimdDetection};
use crate::kernel::machine::fpu;
use crate::kernel::services::diagnostics;

pub(crate) fn initialize_runtime_policy(
    force_no_cpuid: bool,
    force_disable_simd: bool,
    test_mode: bool,
) -> RuntimePolicy {
    let detection = if force_no_cpuid {
        SimdDetection::no_cpuid()
    } else {
        cpu::detect_simd()
    };
    let runtime_state = runtime_state_from_detection(detection, force_disable_simd);
    let policy =
        policy_from_detection(detection, force_no_cpuid, force_disable_simd, runtime_state);
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
    runtime_state: RuntimeStateSummary,
) -> RuntimePolicy {
    if force_no_cpuid {
        return RuntimePolicy::no_cpuid();
    }

    RuntimePolicy::phase3(
        detection.cpuid_supported,
        detection.fxsr,
        detection.forced_scalar || force_disable_simd,
        detection.mmx,
        detection.sse,
        detection.sse2,
        runtime_state,
    )
}

fn runtime_state_from_detection(
    detection: SimdDetection,
    force_disable_simd: bool,
) -> RuntimeStateSummary {
    if force_disable_simd || !detection.cpuid_supported || !detection.has_any_feature() {
        return RuntimeStateSummary::blocked();
    }

    let state = fpu::own_runtime_state(detection);
    if !state.runtime_owned() {
        return RuntimeStateSummary::blocked();
    }

    RuntimeStateSummary::owned(
        state.x87_initialized,
        state.mxcsr_initialized,
        state.mmx_ready,
        state.sse_ready,
        state.sse2_ready,
    )
}

fn emit_runtime_markers(policy: RuntimePolicy) {
    diagnostics::write_line("SIMD_POLICY_OK");

    match policy.mode() {
        SimdExecutionMode::Uninitialized => diagnostics::write_line("SIMD_MODE_UNINITIALIZED"),
        SimdExecutionMode::ScalarOnly => diagnostics::write_line("SIMD_MODE_SCALAR_ONLY"),
        SimdExecutionMode::AccelerationEnabled => {
            diagnostics::write_line("SIMD_MODE_ACCELERATION_ENABLED")
        }
    }

    if policy.has_cpuid() {
        diagnostics::write_line("SIMD_CPUID_PRESENT");
    } else {
        diagnostics::write_line("SIMD_CPUID_ABSENT");
    }

    if policy.fxsr_detected {
        diagnostics::write_line("SIMD_FXSR_OK");
    } else {
        diagnostics::write_line("SIMD_FXSR_ABSENT");
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

    if policy.runtime_owned() {
        diagnostics::write_line("SIMD_RUNTIME_OWNED");
    } else {
        diagnostics::write_line("SIMD_RUNTIME_NOT_OWNED");
    }

    if policy.x87_initialized {
        diagnostics::write_line("SIMD_X87_INIT_OK");
    } else {
        diagnostics::write_line("SIMD_X87_INIT_ABSENT");
    }

    if policy.mxcsr_initialized {
        diagnostics::write_line("SIMD_MXCSR_DEFAULT_OK");
    } else {
        diagnostics::write_line("SIMD_MXCSR_DEFAULT_ABSENT");
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
        ScalarBlockReason::AccelerationDeferred => {
            diagnostics::write_line("SIMD_POLICY_ACCELERATION_DEFERRED")
        }
        ScalarBlockReason::AccelerationEnabled => {
            diagnostics::write_line("SIMD_POLICY_ACCELERATION_ENABLED")
        }
    }
}
