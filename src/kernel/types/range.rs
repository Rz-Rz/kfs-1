#[repr(C)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct KernelRange {
    start: usize,
    end: usize,
}

#[allow(dead_code)]
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
