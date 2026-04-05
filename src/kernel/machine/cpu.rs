#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
use core::arch::asm;

#[cfg(target_arch = "x86")]
use core::arch::x86::__cpuid;
#[cfg(target_arch = "x86_64")]
use core::arch::x86_64::__cpuid;

unsafe extern "C" {
    fn kfs_arch_force_no_cpuid() -> u32;
    fn kfs_arch_force_disable_simd() -> u32;
}

const CPUID_EDX_MMX: u32 = 1 << 23;
const CPUID_EDX_SSE: u32 = 1 << 25;
const CPUID_EDX_SSE2: u32 = 1 << 26;
const FLAGS_ID_BIT: u64 = 1 << 21;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct SimdDetection {
    pub cpuid_supported: bool,
    pub mmx: bool,
    pub sse: bool,
    pub sse2: bool,
    pub forced_scalar: bool,
}

impl SimdDetection {
    pub const fn no_cpuid() -> Self {
        Self {
            cpuid_supported: false,
            mmx: false,
            sse: false,
            sse2: false,
            forced_scalar: false,
        }
    }

    pub const fn forced_scalar() -> Self {
        Self {
            cpuid_supported: true,
            mmx: false,
            sse: false,
            sse2: false,
            forced_scalar: true,
        }
    }

    pub const fn from_cpuid_leaf1_edx(edx: u32) -> Self {
        Self {
            cpuid_supported: true,
            mmx: (edx & CPUID_EDX_MMX) != 0,
            sse: (edx & CPUID_EDX_SSE) != 0,
            sse2: (edx & CPUID_EDX_SSE2) != 0,
            forced_scalar: false,
        }
    }
}

pub fn detect_simd() -> SimdDetection {
    if force_no_cpuid_requested() {
        return SimdDetection::no_cpuid();
    }

    if !cpuid_is_supported() {
        return SimdDetection::no_cpuid();
    }

    if force_disable_simd_requested() {
        return SimdDetection::forced_scalar();
    }

    let leaf = __cpuid(1);
    SimdDetection::from_cpuid_leaf1_edx(leaf.edx)
}

fn force_no_cpuid_requested() -> bool {
    unsafe { kfs_arch_force_no_cpuid() != 0 }
}

fn force_disable_simd_requested() -> bool {
    unsafe { kfs_arch_force_disable_simd() != 0 }
}

#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
fn cpuid_is_supported() -> bool {
    unsafe {
        let original = read_flags();
        let toggled = original ^ FLAGS_ID_BIT;
        write_flags(toggled);
        let observed = read_flags();
        write_flags(original);
        ((observed ^ original) & FLAGS_ID_BIT) != 0
    }
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
fn cpuid_is_supported() -> bool {
    false
}

#[cfg(target_arch = "x86")]
unsafe fn read_flags() -> u64 {
    let flags: u32;
    unsafe {
        asm!("pushfd", "pop {flags:e}", flags = out(reg) flags, options(nomem));
    }
    flags as u64
}

#[cfg(target_arch = "x86")]
unsafe fn write_flags(flags: u64) {
    let flags32 = flags as u32;
    unsafe {
        asm!("push {flags:e}", "popfd", flags = in(reg) flags32, options(nomem));
    }
}

#[cfg(target_arch = "x86_64")]
unsafe fn read_flags() -> u64 {
    let flags: u64;
    unsafe {
        asm!("pushfq", "pop {flags}", flags = out(reg) flags, options(nomem));
    }
    flags
}

#[cfg(target_arch = "x86_64")]
unsafe fn write_flags(flags: u64) {
    unsafe {
        asm!("push {flags}", "popfq", flags = in(reg) flags, options(nomem));
    }
}
