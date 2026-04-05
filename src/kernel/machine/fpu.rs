#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
use core::arch::asm;

use crate::kernel::machine::cpu::SimdDetection;

const CR0_MP: u32 = 1 << 1;
const CR0_EM: u32 = 1 << 2;
const CR0_TS: u32 = 1 << 3;
const CR0_NE: u32 = 1 << 5;
const CR4_OSFXSR: u32 = 1 << 9;
const DEFAULT_MXCSR_MASKED: u32 = 0x1f80;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct SimdRuntimeState {
    pub x87_initialized: bool,
    pub mxcsr_initialized: bool,
    pub mmx_ready: bool,
    pub sse_ready: bool,
    pub sse2_ready: bool,
}

impl SimdRuntimeState {
    pub const fn disabled() -> Self {
        Self {
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
            x87_initialized,
            mxcsr_initialized,
            mmx_ready,
            sse_ready,
            sse2_ready,
        }
    }

    pub const fn runtime_owned(self) -> bool {
        self.x87_initialized
            || self.mxcsr_initialized
            || self.mmx_ready
            || self.sse_ready
            || self.sse2_ready
    }
}

pub fn own_runtime_state(detection: SimdDetection) -> SimdRuntimeState {
    if !detection.cpuid_supported || !detection.has_any_feature() {
        return SimdRuntimeState::disabled();
    }

    unsafe {
        let mut cr0 = read_cr0();
        cr0 &= !(CR0_EM | CR0_TS);
        cr0 |= CR0_MP | CR0_NE;
        write_cr0(cr0);

        let sse_runtime_supported = detection.fxsr && (detection.sse || detection.sse2);
        if sse_runtime_supported {
            let mut cr4 = read_cr4();
            cr4 |= CR4_OSFXSR;
            write_cr4(cr4);
        }

        asm!("fninit", options(nostack, preserves_flags));

        if sse_runtime_supported {
            load_mxcsr(DEFAULT_MXCSR_MASKED);
        }

        SimdRuntimeState::owned(
            true,
            sse_runtime_supported,
            detection.mmx,
            detection.sse && sse_runtime_supported,
            detection.sse2 && sse_runtime_supported,
        )
    }
}

#[cfg(target_arch = "x86")]
unsafe fn read_cr0() -> u32 {
    let value: u32;
    unsafe {
        asm!("mov {value:e}, cr0", value = out(reg) value, options(nostack, preserves_flags));
    }
    value
}

#[cfg(target_arch = "x86")]
unsafe fn write_cr0(value: u32) {
    unsafe {
        asm!("mov cr0, {value:e}", value = in(reg) value, options(nostack, preserves_flags));
    }
}

#[cfg(target_arch = "x86")]
unsafe fn read_cr4() -> u32 {
    let value: u32;
    unsafe {
        asm!("mov {value:e}, cr4", value = out(reg) value, options(nostack, preserves_flags));
    }
    value
}

#[cfg(target_arch = "x86")]
unsafe fn write_cr4(value: u32) {
    unsafe {
        asm!("mov cr4, {value:e}", value = in(reg) value, options(nostack, preserves_flags));
    }
}

#[cfg(target_arch = "x86")]
unsafe fn load_mxcsr(value: u32) {
    unsafe {
        asm!(
            "ldmxcsr [{ptr:e}]",
            ptr = in(reg) &value,
            options(nostack, preserves_flags, readonly)
        );
    }
}

#[cfg(target_arch = "x86_64")]
unsafe fn read_cr0() -> u32 {
    let value: u64;
    unsafe {
        asm!("mov {value}, cr0", value = out(reg) value, options(nostack, preserves_flags));
    }
    value as u32
}

#[cfg(target_arch = "x86_64")]
unsafe fn write_cr0(value: u32) {
    unsafe {
        asm!("mov cr0, {value}", value = in(reg) value as u64, options(nostack, preserves_flags));
    }
}

#[cfg(target_arch = "x86_64")]
unsafe fn read_cr4() -> u32 {
    let value: u64;
    unsafe {
        asm!("mov {value}, cr4", value = out(reg) value, options(nostack, preserves_flags));
    }
    value as u32
}

#[cfg(target_arch = "x86_64")]
unsafe fn write_cr4(value: u32) {
    unsafe {
        asm!("mov cr4, {value}", value = in(reg) value as u64, options(nostack, preserves_flags));
    }
}

#[cfg(target_arch = "x86_64")]
unsafe fn load_mxcsr(value: u32) {
    unsafe {
        asm!(
            "ldmxcsr [{ptr}]",
            ptr = in(reg) &value,
            options(nostack, preserves_flags, readonly)
        );
    }
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
pub fn own_runtime_state(_detection: SimdDetection) -> SimdRuntimeState {
    SimdRuntimeState::disabled()
}
