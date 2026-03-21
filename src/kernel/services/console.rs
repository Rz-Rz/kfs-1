use crate::kernel::drivers::vga_text;

pub(crate) fn write_bytes(bytes: &[u8]) {
    vga_text::write_bytes(bytes);
}

fn write_byte(byte: u8) {
    vga_text::write_bytes(core::slice::from_ref(&byte));
}

pub const MAX_USIZE_DECIMAL_DIGITS: usize = 20;
pub const MAX_USIZE_HEX_DIGITS: usize = core::mem::size_of::<usize>() * 2;
pub const MAX_ISIZE_DECIMAL_DIGITS: usize = MAX_USIZE_DECIMAL_DIGITS + 1;

pub fn format_usize_decimal(
    mut value: usize,
    buffer: &mut [u8; MAX_USIZE_DECIMAL_DIGITS],
) -> &[u8] {
    let mut idx = MAX_USIZE_DECIMAL_DIGITS;

    if value == 0 {
        idx -= 1;
        unsafe {
            core::ptr::write(buffer.as_mut_ptr().add(idx), b'0');
            return core::slice::from_raw_parts(buffer.as_ptr().add(idx), 1);
        }
    }

    while value > 0 {
        idx -= 1;
        unsafe {
            core::ptr::write(buffer.as_mut_ptr().add(idx), b'0' + ((value % 10) as u8));
        }
        value /= 10;
    }

    unsafe { core::slice::from_raw_parts(buffer.as_ptr().add(idx), MAX_USIZE_DECIMAL_DIGITS - idx) }
}

pub fn format_usize_hex(mut value: usize, buffer: &mut [u8; MAX_USIZE_HEX_DIGITS]) -> &[u8] {
    let mut idx = MAX_USIZE_HEX_DIGITS;

    if value == 0 {
        idx -= 1;
        unsafe {
            core::ptr::write(buffer.as_mut_ptr().add(idx), b'0');
            return core::slice::from_raw_parts(buffer.as_ptr().add(idx), 1);
        }
    }

    while value > 0 {
        idx -= 1;
        let nibble = (value & 0x0f) as u8;
        let digit = if nibble < 10 {
            b'0' + nibble
        } else {
            b'a' + (nibble - 10)
        };
        unsafe {
            core::ptr::write(buffer.as_mut_ptr().add(idx), digit);
        }
        value >>= 4;
    }

    unsafe { core::slice::from_raw_parts(buffer.as_ptr().add(idx), MAX_USIZE_HEX_DIGITS - idx) }
}

pub fn format_isize_decimal(value: isize, buffer: &mut [u8; MAX_ISIZE_DECIMAL_DIGITS]) -> &[u8] {
    let mut idx = MAX_ISIZE_DECIMAL_DIGITS;
    let negative = value < 0;
    let mut magnitude = if negative {
        (value as usize).wrapping_neg()
    } else {
        value as usize
    };

    if magnitude == 0 {
        idx -= 1;
        unsafe {
            core::ptr::write(buffer.as_mut_ptr().add(idx), b'0');
        }
    } else {
        while magnitude > 0 {
            idx -= 1;
            unsafe {
                core::ptr::write(buffer.as_mut_ptr().add(idx), b'0' + ((magnitude % 10) as u8));
            }
            magnitude /= 10;
        }
    }

    if negative {
        idx -= 1;
        unsafe {
            core::ptr::write(buffer.as_mut_ptr().add(idx), b'-');
        }
    }

    unsafe { core::slice::from_raw_parts(buffer.as_ptr().add(idx), MAX_ISIZE_DECIMAL_DIGITS - idx) }
}

fn emit_slice<F>(text: &[u8], emit: &mut F)
where
    F: FnMut(u8),
{
    let mut idx: usize = 0;
    while idx < text.len() {
        let byte = unsafe { core::ptr::read(text.as_ptr().add(idx)) };
        emit(byte);
        idx += 1;
    }
}

fn emit_c_string<F>(text: *const u8, emit: &mut F)
where
    F: FnMut(u8),
{
    let mut idx: usize = 0;
    loop {
        let byte = unsafe { core::ptr::read(text.add(idx)) };
        if byte == 0 {
            return;
        }
        emit(byte);
        idx += 1;
    }
}

fn emit_missing_arg<F>(emit: &mut F)
where
    F: FnMut(u8),
{
    emit_slice(b"<arg?>", emit);
}

fn next_arg(args: *const usize, arg_count: usize, arg_index: &mut usize) -> Option<usize> {
    if *arg_index >= arg_count {
        return None;
    }
    let value = unsafe { core::ptr::read(args.add(*arg_index)) };
    *arg_index += 1;
    Some(value)
}

pub fn render_printf_with_args<F>(format: *const u8, args: *const usize, arg_count: usize, mut emit: F)
where
    F: FnMut(u8),
{
    let mut idx: usize = 0;
    let mut arg_index: usize = 0;

    loop {
        let byte = unsafe { core::ptr::read(format.add(idx)) };
        if byte == 0 {
            return;
        }

        if byte != b'%' {
            emit(byte);
            idx += 1;
            continue;
        }

        idx += 1;
        let specifier = unsafe { core::ptr::read(format.add(idx)) };
        if specifier == 0 {
            emit(b'%');
            return;
        }

        match specifier {
            b'%' => emit(b'%'),
            b'u' => {
                if let Some(value) = next_arg(args, arg_count, &mut arg_index) {
                    let mut digits_uninit =
                        core::mem::MaybeUninit::<[u8; MAX_USIZE_DECIMAL_DIGITS]>::uninit();
                    let digits = unsafe { &mut *digits_uninit.as_mut_ptr() };
                    emit_slice(format_usize_decimal(value, digits), &mut emit);
                } else {
                    emit_missing_arg(&mut emit);
                }
            }
            b'd' => {
                if let Some(value) = next_arg(args, arg_count, &mut arg_index) {
                    let mut digits_uninit =
                        core::mem::MaybeUninit::<[u8; MAX_ISIZE_DECIMAL_DIGITS]>::uninit();
                    let digits = unsafe { &mut *digits_uninit.as_mut_ptr() };
                    emit_slice(format_isize_decimal(value as isize, digits), &mut emit);
                } else {
                    emit_missing_arg(&mut emit);
                }
            }
            b'x' => {
                if let Some(value) = next_arg(args, arg_count, &mut arg_index) {
                    let mut digits_uninit =
                        core::mem::MaybeUninit::<[u8; MAX_USIZE_HEX_DIGITS]>::uninit();
                    let digits = unsafe { &mut *digits_uninit.as_mut_ptr() };
                    emit_slice(format_usize_hex(value, digits), &mut emit);
                } else {
                    emit_missing_arg(&mut emit);
                }
            }
            b'c' => {
                if let Some(value) = next_arg(args, arg_count, &mut arg_index) {
                    emit((value & 0xff) as u8);
                } else {
                    emit_missing_arg(&mut emit);
                }
            }
            b's' => {
                if let Some(value) = next_arg(args, arg_count, &mut arg_index) {
                    let ptr = value as *const u8;
                    if ptr.is_null() {
                        emit_slice(b"(null)", &mut emit);
                    } else {
                        emit_c_string(ptr, &mut emit);
                    }
                } else {
                    emit_missing_arg(&mut emit);
                }
            }
            _ => {
                emit(b'%');
                emit(specifier);
            }
        }

        idx += 1;
    }
}

pub fn write_usize(value: usize) {
    let mut digits_uninit = core::mem::MaybeUninit::<[u8; MAX_USIZE_DECIMAL_DIGITS]>::uninit();
    let digits = unsafe { &mut *digits_uninit.as_mut_ptr() };
    let rendered = format_usize_decimal(value, digits);
    emit_slice(rendered, &mut write_byte);
}

pub fn printf(format: *const u8, value: usize) {
    printf_args(format, &value as *const usize, 1);
}

pub fn printf_args(format: *const u8, args: *const usize, arg_count: usize) {
    render_printf_with_args(format, args, arg_count, write_byte);
}

pub fn printk(format: *const u8, value: usize) {
    printf(format, value);
}

pub fn printk_args(format: *const u8, args: *const usize, arg_count: usize) {
    printf_args(format, args, arg_count);
}
