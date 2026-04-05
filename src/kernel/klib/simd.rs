#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum SimdFeature {
    Mmx,
    Sse,
    Sse2,
}

#[repr(u8)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum SimdExecutionMode {
    Uninitialized = 0,
    ScalarOnly = 1,
}

#[repr(u8)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum ScalarBlockReason {
    Uninitialized = 0,
    NoCpuid = 1,
    NoSupportedFeatures = 2,
    ForcedByPolicy = 3,
    RuntimeStateDisabled = 4,
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct RuntimePolicy {
    pub mmx_detected: bool,
    pub sse_detected: bool,
    pub sse2_detected: bool,
    pub mmx_allowed: bool,
    pub sse_allowed: bool,
    pub sse2_allowed: bool,
    pub block_reason: ScalarBlockReason,
}

impl RuntimePolicy {
    pub const fn uninitialized() -> Self {
        Self {
            mmx_detected: false,
            sse_detected: false,
            sse2_detected: false,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::Uninitialized,
        }
    }

    pub const fn phase2(
        cpuid_supported: bool,
        forced_scalar: bool,
        mmx: bool,
        sse: bool,
        sse2: bool,
    ) -> Self {
        if !cpuid_supported {
            return Self::no_cpuid();
        }

        if forced_scalar {
            return Self::forced_scalar(mmx, sse, sse2);
        }

        if !mmx && !sse && !sse2 {
            return Self::no_supported_features();
        }

        Self::runtime_blocked(mmx, sse, sse2)
    }

    pub const fn no_cpuid() -> Self {
        Self {
            mmx_detected: false,
            sse_detected: false,
            sse2_detected: false,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::NoCpuid,
        }
    }

    pub const fn no_supported_features() -> Self {
        Self {
            mmx_detected: false,
            sse_detected: false,
            sse2_detected: false,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::NoSupportedFeatures,
        }
    }

    pub const fn forced_scalar(mmx: bool, sse: bool, sse2: bool) -> Self {
        Self {
            mmx_detected: mmx,
            sse_detected: sse,
            sse2_detected: sse2,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::ForcedByPolicy,
        }
    }

    pub const fn runtime_blocked(mmx: bool, sse: bool, sse2: bool) -> Self {
        Self {
            mmx_detected: mmx,
            sse_detected: sse,
            sse2_detected: sse2,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::RuntimeStateDisabled,
        }
    }

    pub const fn has_cpuid(self) -> bool {
        self.mmx_detected
            || self.sse_detected
            || self.sse2_detected
            || matches!(
                self.block_reason,
                ScalarBlockReason::NoSupportedFeatures
                    | ScalarBlockReason::ForcedByPolicy
                    | ScalarBlockReason::RuntimeStateDisabled
            )
    }

    pub const fn is_scalar_only(self) -> bool {
        !self.mmx_allowed && !self.sse_allowed && !self.sse2_allowed
    }

    pub const fn mode(self) -> SimdExecutionMode {
        match self.block_reason {
            ScalarBlockReason::Uninitialized => SimdExecutionMode::Uninitialized,
            ScalarBlockReason::NoCpuid
            | ScalarBlockReason::NoSupportedFeatures
            | ScalarBlockReason::ForcedByPolicy
            | ScalarBlockReason::RuntimeStateDisabled => SimdExecutionMode::ScalarOnly,
        }
    }

    pub const fn supports(self, feature: SimdFeature) -> bool {
        match feature {
            SimdFeature::Mmx => self.mmx_detected,
            SimdFeature::Sse => self.sse_detected,
            SimdFeature::Sse2 => self.sse2_detected,
        }
    }

    pub const fn allows(self, feature: SimdFeature) -> bool {
        match feature {
            SimdFeature::Mmx => self.mmx_allowed,
            SimdFeature::Sse => self.sse_allowed,
            SimdFeature::Sse2 => self.sse2_allowed,
        }
    }
}

static mut RUNTIME_POLICY: RuntimePolicy = RuntimePolicy::uninitialized();

pub fn install_runtime_policy(policy: RuntimePolicy) {
    unsafe {
        RUNTIME_POLICY = policy;
    }
}

pub fn runtime_policy() -> RuntimePolicy {
    unsafe {
        RUNTIME_POLICY
    }
}

pub fn reset_runtime_policy() {
    install_runtime_policy(RuntimePolicy::uninitialized());
}

pub fn simd_mode() -> SimdExecutionMode {
    runtime_policy().mode()
}

pub fn mmx_allowed() -> bool {
    runtime_policy().mmx_allowed
}

pub fn sse_allowed() -> bool {
    runtime_policy().sse_allowed
}

pub fn sse2_allowed() -> bool {
    runtime_policy().sse2_allowed
}
