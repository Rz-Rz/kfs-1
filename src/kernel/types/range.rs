#[repr(C)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct KernelRange {
    start: usize,
    end: usize,
}

impl KernelRange {
    pub const fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }

    pub const fn start(self) -> usize {
        self.start
    }

    pub const fn end(self) -> usize {
        self.end
    }

    pub const fn is_empty(self) -> bool {
        self.start >= self.end
    }

    pub const fn contains(self, addr: usize) -> bool {
        self.start <= addr && addr < self.end
    }

    pub const fn len(self) -> usize {
        self.end.saturating_sub(self.start)
    }
}

pub fn layout_order_is_sane(
    kernel: KernelRange,
    bss: KernelRange,
    layout_override: bool,
) -> bool {
    if layout_override {
        return false;
    }

    let kernel_lo = kernel.start();
    let kernel_hi = kernel.end();
    let bss_lo = bss.start();
    let bss_hi = bss.end();

    !kernel.is_empty() && kernel_lo <= bss_lo && bss_lo <= bss_hi && bss_hi <= kernel_hi
}
