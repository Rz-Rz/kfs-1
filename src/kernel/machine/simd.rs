use core::sync::atomic::{AtomicU8, Ordering};

const CPUID_BIT: u32 = 1 << 21;
const MMX_BIT: u32 = 1 << 23;
const SSE_BIT: u32 = 1 << 25;
const SSE2_BIT: u32 = 1 << 26;

const SUPPORT_CPUID: u8 = 1 << 0;
const SUPPORT_MMX: u8 = 1 << 1;
const SUPPORT_SSE: u8 = 1 << 2;
const SUPPORT_SSE2: u8 = 1 << 3;

static DETECTED_SUPPORT_BITS: AtomicU8 = AtomicU8::new(0);
static EXECUTION_MODE_BITS: AtomicU8 = AtomicU8::new(SimdExecutionMode::Uninitialized as u8);

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum SimdFeature {
    Mmx,
    Sse,
    Sse2,
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct SimdSupport {
    bits: u8,
}

impl SimdSupport {
    pub const fn none() -> Self {
        Self { bits: 0 }
    }

    pub const fn from_cpuid_edx(has_cpuid: bool, edx: u32) -> Self {
        if !has_cpuid {
            return Self::none();
        }

        let mut bits = SUPPORT_CPUID;
        if (edx & MMX_BIT) != 0 {
            bits |= SUPPORT_MMX;
        }
        if (edx & SSE_BIT) != 0 {
            bits |= SUPPORT_SSE;
        }
        if (edx & SSE2_BIT) != 0 {
            bits |= SUPPORT_SSE2;
        }

        Self { bits }
    }

    const fn from_bits(bits: u8) -> Self {
        Self { bits }
    }

    const fn bits(self) -> u8 {
        self.bits
    }

    pub const fn has_cpuid(self) -> bool {
        (self.bits & SUPPORT_CPUID) != 0
    }

    pub const fn supports(self, feature: SimdFeature) -> bool {
        let bit = match feature {
            SimdFeature::Mmx => SUPPORT_MMX,
            SimdFeature::Sse => SUPPORT_SSE,
            SimdFeature::Sse2 => SUPPORT_SSE2,
        };
        (self.bits & bit) != 0
    }
}

#[repr(u8)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum SimdExecutionMode {
    Uninitialized = 0,
    ScalarOnly = 1,
}

impl SimdExecutionMode {
    const fn from_bits(bits: u8) -> Self {
        match bits {
            1 => Self::ScalarOnly,
            _ => Self::Uninitialized,
        }
    }
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct SimdPolicySnapshot {
    support: SimdSupport,
    mode: SimdExecutionMode,
}

impl SimdPolicySnapshot {
    pub const fn uninitialized() -> Self {
        Self {
            support: SimdSupport::none(),
            mode: SimdExecutionMode::Uninitialized,
        }
    }

    pub const fn phase2_scalar(support: SimdSupport) -> Self {
        Self {
            support,
            mode: SimdExecutionMode::ScalarOnly,
        }
    }

    pub const fn detected_support(self) -> SimdSupport {
        self.support
    }

    pub const fn mode(self) -> SimdExecutionMode {
        self.mode
    }

    pub const fn allows(self, _feature: SimdFeature) -> bool {
        false
    }
}

pub fn initialize_phase2_policy() -> SimdPolicySnapshot {
    let policy = SimdPolicySnapshot::phase2_scalar(detect_support());
    DETECTED_SUPPORT_BITS.store(policy.detected_support().bits(), Ordering::Relaxed);
    EXECUTION_MODE_BITS.store(policy.mode() as u8, Ordering::Relaxed);
    policy
}

pub fn current_policy() -> SimdPolicySnapshot {
    let support = SimdSupport::from_bits(DETECTED_SUPPORT_BITS.load(Ordering::Relaxed));
    let mode = SimdExecutionMode::from_bits(EXECUTION_MODE_BITS.load(Ordering::Relaxed));
    SimdPolicySnapshot { support, mode }
}

fn detect_support() -> SimdSupport {
    if !cpuid_is_supported() {
        return SimdSupport::none();
    }

    SimdSupport::from_cpuid_edx(true, cpuid_leaf1_edx())
}

#[cfg(target_arch = "x86")]
fn cpuid_leaf1_edx() -> u32 {
    unsafe { core::arch::x86::__cpuid(1).edx }
}

#[cfg(target_arch = "x86_64")]
fn cpuid_leaf1_edx() -> u32 {
    unsafe { core::arch::x86_64::__cpuid(1).edx }
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
fn cpuid_leaf1_edx() -> u32 {
    0
}

#[cfg(target_arch = "x86")]
fn cpuid_is_supported() -> bool {
    unsafe {
        let original = read_flags32();
        let toggled = original ^ CPUID_BIT;
        write_flags32(toggled);
        let observed = read_flags32();
        write_flags32(original);
        ((observed ^ original) & CPUID_BIT) != 0
    }
}

#[cfg(target_arch = "x86_64")]
fn cpuid_is_supported() -> bool {
    true
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
fn cpuid_is_supported() -> bool {
    false
}

#[cfg(target_arch = "x86")]
unsafe fn read_flags32() -> u32 {
    let value: u32;
    unsafe {
        core::arch::asm!("pushfd", "pop {}", out(reg) value);
    }
    value
}

#[cfg(target_arch = "x86")]
unsafe fn write_flags32(value: u32) {
    unsafe {
        core::arch::asm!("push {}", "popfd", in(reg) value);
    }
}
