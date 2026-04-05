use kfs::kernel::machine::simd::{
    SimdExecutionMode, SimdFeature, SimdPolicySnapshot, SimdSupport,
};

#[test]
fn cpuid_absence_forces_no_simd_support() {
    let support = SimdSupport::from_cpuid_edx(false, u32::MAX);

    assert!(!support.has_cpuid());
    assert!(!support.supports(SimdFeature::Mmx));
    assert!(!support.supports(SimdFeature::Sse));
    assert!(!support.supports(SimdFeature::Sse2));
}

#[test]
fn cpuid_feature_bits_map_to_mmx_sse_and_sse2() {
    let edx = (1u32 << 23) | (1u32 << 25) | (1u32 << 26);
    let support = SimdSupport::from_cpuid_edx(true, edx);

    assert!(support.has_cpuid());
    assert!(support.supports(SimdFeature::Mmx));
    assert!(support.supports(SimdFeature::Sse));
    assert!(support.supports(SimdFeature::Sse2));
}

#[test]
fn missing_feature_bits_stay_disabled() {
    let support = SimdSupport::from_cpuid_edx(true, 1u32 << 23);

    assert!(support.has_cpuid());
    assert!(support.supports(SimdFeature::Mmx));
    assert!(!support.supports(SimdFeature::Sse));
    assert!(!support.supports(SimdFeature::Sse2));
}

#[test]
fn phase2_policy_is_scalar_only_even_when_hardware_support_exists() {
    let support = SimdSupport::from_cpuid_edx(true, (1u32 << 23) | (1u32 << 25) | (1u32 << 26));
    let policy = SimdPolicySnapshot::phase2_scalar(support);

    assert_eq!(policy.mode(), SimdExecutionMode::ScalarOnly);
    assert!(policy.detected_support().supports(SimdFeature::Sse2));
    assert!(!policy.allows(SimdFeature::Mmx));
    assert!(!policy.allows(SimdFeature::Sse));
    assert!(!policy.allows(SimdFeature::Sse2));
}

#[test]
fn uninitialized_policy_denies_all_acceleration() {
    let policy = SimdPolicySnapshot::uninitialized();

    assert_eq!(policy.mode(), SimdExecutionMode::Uninitialized);
    assert!(!policy.detected_support().has_cpuid());
    assert!(!policy.allows(SimdFeature::Mmx));
    assert!(!policy.allows(SimdFeature::Sse));
    assert!(!policy.allows(SimdFeature::Sse2));
}
