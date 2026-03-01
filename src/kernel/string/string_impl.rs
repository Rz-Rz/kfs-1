pub unsafe fn strlen(ptr: *const u8) -> usize {
    let mut len: usize = 0;
    loop {
        let byte = unsafe { core::ptr::read_volatile(ptr.add(len)) };
        if byte == 0 {
            return len;
        }
        len += 1;
    }
}

pub unsafe fn strcmp(lhs: *const u8, rhs: *const u8) -> i32 {
    let mut idx: usize = 0;
    loop {
        let l = unsafe { core::ptr::read_volatile(lhs.add(idx)) };
        let r = unsafe { core::ptr::read_volatile(rhs.add(idx)) };

        if l != r {
            return (l as i32) - (r as i32);
        }

        if l == 0 {
            return 0;
        }

        idx += 1;
    }
}

