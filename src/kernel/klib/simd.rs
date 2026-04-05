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
    AccelerationDeferred = 5,
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct RuntimePolicy {
    pub cpuid_supported: bool,
    pub fxsr_detected: bool,
    pub mmx_detected: bool,
    pub sse_detected: bool,
    pub sse2_detected: bool,
    pub x87_initialized: bool,
    pub mxcsr_initialized: bool,
    pub mmx_ready: bool,
    pub sse_ready: bool,
    pub sse2_ready: bool,
    pub mmx_allowed: bool,
    pub sse_allowed: bool,
    pub sse2_allowed: bool,
    pub block_reason: ScalarBlockReason,
}

impl RuntimePolicy {
    pub const fn uninitialized() -> Self {
        Self {
            cpuid_supported: false,
            fxsr_detected: false,
            mmx_detected: false,
            sse_detected: false,
            sse2_detected: false,
            x87_initialized: false,
            mxcsr_initialized: false,
            mmx_ready: false,
            sse_ready: false,
            sse2_ready: false,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::Uninitialized,
        }
    }

    pub const fn phase2(
        cpuid_supported: bool,
        fxsr: bool,
        forced_scalar: bool,
        mmx: bool,
        sse: bool,
        sse2: bool,
    ) -> Self {
        if !cpuid_supported {
            return Self::no_cpuid();
        }

        if forced_scalar {
            return Self::forced_scalar(fxsr, mmx, sse, sse2);
        }

        if !mmx && !sse && !sse2 {
            return Self::no_supported_features();
        }

        Self::runtime_blocked(fxsr, mmx, sse, sse2)
    }

    pub const fn phase3(
        cpuid_supported: bool,
        fxsr: bool,
        forced_scalar: bool,
        mmx: bool,
        sse: bool,
        sse2: bool,
        runtime_state: RuntimeStateSummary,
    ) -> Self {
        if !cpuid_supported {
            return Self::no_cpuid();
        }

        if forced_scalar {
            return Self::forced_scalar(fxsr, mmx, sse, sse2);
        }

        if !mmx && !sse && !sse2 {
            return Self::no_supported_features();
        }

        if runtime_state.runtime_owned {
            return Self::acceleration_deferred(
                fxsr,
                mmx,
                sse,
                sse2,
                runtime_state.x87_initialized,
                runtime_state.mxcsr_initialized,
                runtime_state.mmx_ready,
                runtime_state.sse_ready,
                runtime_state.sse2_ready,
            );
        }

        Self::runtime_blocked(fxsr, mmx, sse, sse2)
    }

    pub const fn no_cpuid() -> Self {
        Self {
            cpuid_supported: false,
            fxsr_detected: false,
            mmx_detected: false,
            sse_detected: false,
            sse2_detected: false,
            x87_initialized: false,
            mxcsr_initialized: false,
            mmx_ready: false,
            sse_ready: false,
            sse2_ready: false,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::NoCpuid,
        }
    }

    pub const fn no_supported_features() -> Self {
        Self {
            cpuid_supported: true,
            fxsr_detected: false,
            mmx_detected: false,
            sse_detected: false,
            sse2_detected: false,
            x87_initialized: false,
            mxcsr_initialized: false,
            mmx_ready: false,
            sse_ready: false,
            sse2_ready: false,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::NoSupportedFeatures,
        }
    }

    pub const fn forced_scalar(fxsr: bool, mmx: bool, sse: bool, sse2: bool) -> Self {
        Self {
            cpuid_supported: true,
            fxsr_detected: fxsr,
            mmx_detected: mmx,
            sse_detected: sse,
            sse2_detected: sse2,
            x87_initialized: false,
            mxcsr_initialized: false,
            mmx_ready: false,
            sse_ready: false,
            sse2_ready: false,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::ForcedByPolicy,
        }
    }

    pub const fn runtime_blocked(fxsr: bool, mmx: bool, sse: bool, sse2: bool) -> Self {
        Self {
            cpuid_supported: true,
            fxsr_detected: fxsr,
            mmx_detected: mmx,
            sse_detected: sse,
            sse2_detected: sse2,
            x87_initialized: false,
            mxcsr_initialized: false,
            mmx_ready: false,
            sse_ready: false,
            sse2_ready: false,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::RuntimeStateDisabled,
        }
    }

    pub const fn acceleration_deferred(
        fxsr: bool,
        mmx: bool,
        sse: bool,
        sse2: bool,
        x87_initialized: bool,
        mxcsr_initialized: bool,
        mmx_ready: bool,
        sse_ready: bool,
        sse2_ready: bool,
    ) -> Self {
        Self {
            cpuid_supported: true,
            fxsr_detected: fxsr,
            mmx_detected: mmx,
            sse_detected: sse,
            sse2_detected: sse2,
            x87_initialized,
            mxcsr_initialized,
            mmx_ready,
            sse_ready,
            sse2_ready,
            mmx_allowed: false,
            sse_allowed: false,
            sse2_allowed: false,
            block_reason: ScalarBlockReason::AccelerationDeferred,
        }
    }

    pub const fn has_cpuid(self) -> bool {
        self.cpuid_supported
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
            | ScalarBlockReason::RuntimeStateDisabled
            | ScalarBlockReason::AccelerationDeferred => SimdExecutionMode::ScalarOnly,
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

    pub const fn ready(self, feature: SimdFeature) -> bool {
        match feature {
            SimdFeature::Mmx => self.mmx_ready,
            SimdFeature::Sse => self.sse_ready,
            SimdFeature::Sse2 => self.sse2_ready,
        }
    }

    pub const fn runtime_owned(self) -> bool {
        self.x87_initialized || self.mxcsr_initialized || self.mmx_ready || self.sse_ready || self.sse2_ready
    }
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct RuntimeStateSummary {
    pub runtime_owned: bool,
    pub x87_initialized: bool,
    pub mxcsr_initialized: bool,
    pub mmx_ready: bool,
    pub sse_ready: bool,
    pub sse2_ready: bool,
}

impl RuntimeStateSummary {
    pub const fn blocked() -> Self {
        Self {
            runtime_owned: false,
            x87_initialized: false,
            mxcsr_initialized: false,
            mmx_ready: false,
            sse_ready: false,
            sse2_ready: false,
        }
    }

    pub const fn owned(
        x87_initialized: bool,
        mxcsr_initialized: bool,
        mmx_ready: bool,
        sse_ready: bool,
        sse2_ready: bool,
    ) -> Self {
        Self {
            runtime_owned: true,
            x87_initialized,
            mxcsr_initialized,
            mmx_ready,
            sse_ready,
            sse2_ready,
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
