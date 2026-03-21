#[inline(never)]
pub(super) unsafe fn strlen(ptr: *const u8) -> usize {
    let mut len: usize = 0;
    loop {
        let byte = unsafe { ptr.add(len).read() };
        if byte == 0 {
            return len;
        }
        len += 1;
    }
}

#[inline(never)]
pub(super) unsafe fn strcmp(lhs: *const u8, rhs: *const u8) -> i32 {
    let mut idx: usize = 0;
    loop {
        let l = unsafe { lhs.add(idx).read() };
        let r = unsafe { rhs.add(idx).read() };

        if l != r {
            return (l as i32) - (r as i32);
        }

        if l == 0 {
            return 0;
        }

        idx += 1;
    }
}
