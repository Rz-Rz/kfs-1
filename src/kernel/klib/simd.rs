#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum ScalarBlockReason {
    Uninitialized,
    NoCpuid,
    ForcedByPolicy,
    RuntimeStateDisabled,
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

    pub const fn forced_scalar() -> Self {
        Self {
            mmx_detected: false,
            sse_detected: false,
            sse2_detected: false,
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
}

static mut RUNTIME_POLICY: RuntimePolicy = RuntimePolicy::uninitialized();

pub fn install_runtime_policy(policy: RuntimePolicy) {
    unsafe {
        RUNTIME_POLICY = policy;
    }
}

pub fn runtime_policy() -> RuntimePolicy {
    unsafe { RUNTIME_POLICY }
}

pub fn reset_runtime_policy() {
    install_runtime_policy(RuntimePolicy::uninitialized());
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
