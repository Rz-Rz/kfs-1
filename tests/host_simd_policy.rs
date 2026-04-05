use kfs::kernel::klib::memory;
use kfs::kernel::klib::simd::{self, RuntimePolicy, ScalarBlockReason, SimdExecutionMode, SimdFeature};
use kfs::kernel::machine::cpu::SimdDetection;

#[test]
fn cpuid_absence_forces_no_simd_support() {
    let policy = RuntimePolicy::no_cpuid();

    assert_eq!(policy.block_reason, ScalarBlockReason::NoCpuid);
    assert_eq!(policy.mode(), SimdExecutionMode::ScalarOnly);
    assert!(!policy.has_cpuid());
    assert!(!policy.supports(SimdFeature::Mmx));
    assert!(!policy.supports(SimdFeature::Sse));
    assert!(!policy.supports(SimdFeature::Sse2));
}

#[test]
fn cpuid_feature_bits_map_to_mmx_sse_and_sse2() {
    let detection =
        SimdDetection::from_cpuid_leaf1_edx((1u32 << 23) | (1u32 << 24) | (1u32 << 25) | (1u32 << 26), false);

    assert!(detection.cpuid_supported);
    assert!(detection.fxsr);
    assert!(detection.mmx);
    assert!(detection.sse);
    assert!(detection.sse2);
    assert!(!detection.forced_scalar);
}

#[test]
fn missing_feature_bits_stay_disabled() {
    let detection = SimdDetection::from_cpuid_leaf1_edx(1u32 << 23, false);

    assert!(detection.cpuid_supported);
    assert!(!detection.fxsr);
    assert!(detection.mmx);
    assert!(!detection.sse);
    assert!(!detection.sse2);
}

#[test]
fn uninitialized_policy_denies_all_acceleration() {
    simd::reset_runtime_policy();

    let policy = simd::runtime_policy();

    assert_eq!(policy.block_reason, ScalarBlockReason::Uninitialized);
    assert_eq!(policy.mode(), SimdExecutionMode::Uninitialized);
    assert!(!policy.has_cpuid());
    assert!(!simd::mmx_allowed());
    assert!(!simd::sse_allowed());
    assert!(!simd::sse2_allowed());
}

#[test]
fn runtime_blocked_policy_preserves_detected_support_but_denies_execution() {
    simd::install_runtime_policy(RuntimePolicy::runtime_blocked(true, true, true, true));

    let policy = simd::runtime_policy();

    assert_eq!(policy.block_reason, ScalarBlockReason::RuntimeStateDisabled);
    assert_eq!(policy.mode(), SimdExecutionMode::ScalarOnly);
    assert!(policy.fxsr_detected);
    assert!(policy.mmx_detected);
    assert!(policy.sse_detected);
    assert!(policy.sse2_detected);
    assert!(!policy.runtime_owned());
    assert!(policy.supports(SimdFeature::Mmx));
    assert!(policy.supports(SimdFeature::Sse));
    assert!(policy.supports(SimdFeature::Sse2));
    assert!(!simd::mmx_allowed());
    assert!(!simd::sse_allowed());
    assert!(!simd::sse2_allowed());
}

#[test]
fn forced_scalar_policy_denies_all_acceleration() {
    simd::install_runtime_policy(RuntimePolicy::forced_scalar(true, true, true, false));

    let policy = simd::runtime_policy();

    assert_eq!(policy.block_reason, ScalarBlockReason::ForcedByPolicy);
    assert_eq!(policy.mode(), SimdExecutionMode::ScalarOnly);
    assert!(policy.fxsr_detected);
    assert!(policy.supports(SimdFeature::Mmx));
    assert!(policy.supports(SimdFeature::Sse));
    assert!(!policy.supports(SimdFeature::Sse2));
    assert!(!simd::mmx_allowed());
    assert!(!simd::sse_allowed());
    assert!(!simd::sse2_allowed());
}

#[test]
fn no_cpuid_policy_denies_all_acceleration() {
    simd::install_runtime_policy(RuntimePolicy::no_cpuid());

    let policy = simd::runtime_policy();

    assert_eq!(policy.block_reason, ScalarBlockReason::NoCpuid);
    assert_eq!(policy.mode(), SimdExecutionMode::ScalarOnly);
    assert!(!simd::mmx_allowed());
    assert!(!simd::sse_allowed());
    assert!(!simd::sse2_allowed());
}

#[test]
fn no_supported_features_still_counts_as_scalar_policy() {
    let policy = RuntimePolicy::phase2(true, false, false, false, false, false);

    assert_eq!(policy.block_reason, ScalarBlockReason::NoSupportedFeatures);
    assert_eq!(policy.mode(), SimdExecutionMode::ScalarOnly);
    assert!(policy.has_cpuid());
    assert!(policy.is_scalar_only());
}

#[test]
fn runtime_owned_policy_is_observable_but_still_scalar_only() {
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

    let policy = simd::runtime_policy();

    assert_eq!(policy.block_reason, ScalarBlockReason::AccelerationDeferred);
    assert_eq!(policy.mode(), SimdExecutionMode::ScalarOnly);
    assert!(policy.runtime_owned());
    assert!(policy.x87_initialized);
    assert!(policy.mxcsr_initialized);
    assert!(policy.ready(SimdFeature::Mmx));
    assert!(policy.ready(SimdFeature::Sse));
    assert!(policy.ready(SimdFeature::Sse2));
    assert!(!policy.allows(SimdFeature::Mmx));
    assert!(!policy.allows(SimdFeature::Sse));
    assert!(!policy.allows(SimdFeature::Sse2));
}

#[test]
fn guardrails_reach_klib_without_arch_shortcuts() {
    simd::reset_runtime_policy();

    let policy = memory::simd_policy();

    assert_eq!(memory::simd_mode(), SimdExecutionMode::Uninitialized);
    assert_eq!(policy.block_reason, ScalarBlockReason::Uninitialized);
    assert!(!memory::simd_acceleration_allowed(SimdFeature::Mmx));
    assert!(!memory::simd_acceleration_allowed(SimdFeature::Sse));
    assert!(!memory::simd_acceleration_allowed(SimdFeature::Sse2));
}
