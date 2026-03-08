#[inline(never)]
pub unsafe fn string_len_impl(ptr: *const u8) -> usize {
    let mut len: usize = 0;
    loop {
        let byte = unsafe { ptr.add(len).read() };
        if byte == 0 {
            return len;
        }
        len += 1;
    }
}

#[allow(dead_code)]
pub unsafe fn strlen(ptr: *const u8) -> usize {
    unsafe { string_len_impl(ptr) }
}

#[inline(never)]
pub unsafe fn string_cmp_impl(lhs: *const u8, rhs: *const u8) -> i32 {
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

#[allow(dead_code)]
pub unsafe fn strcmp(lhs: *const u8, rhs: *const u8) -> i32 {
    unsafe { string_cmp_impl(lhs, rhs) }
}
