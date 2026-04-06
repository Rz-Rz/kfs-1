use crate::kernel::core::entry;
use crate::kernel::klib::memory::MemoryBackend;
use crate::kernel::klib::{memory, string};
use crate::kernel::services::console;
use crate::kernel::services::diagnostics;
use crate::kernel::services::simd;
use crate::kernel::types::range::layout_order_is_sane;

// At this stage we only care which basic piece is broken badly enough to stop boot.
#[derive(Copy, Clone)]
pub(crate) enum EarlyInitFailure {
    BssCanary,
    Layout,
    StringHelpers,
    MemoryHelpers,
}

// This is the first little sanity-check pass before the rest of the kernel takes over.
// We make sure `.bss` was cleared, the linker layout looks sane, SIMD policy is installed, and
// the tiny string/memory helpers behave. If one of those is wrong, we stop right away so later
// failures do not send us looking in the wrong place.
pub(crate) fn run_early_init() -> Result<(), EarlyInitFailure> {
    // If `.bss` was not cleared before we reached Rust, any zero-initialized global is suspect.
    if !entry::bss_canary_is_zero() {
        return Err(EarlyInitFailure::BssCanary);
    }

    if entry::is_test_mode() {
        diagnostics::write_line("BSS_OK");
    }

    if !layout_is_sane() {
        return Err(EarlyInitFailure::Layout);
    }

    if entry::is_test_mode() {
        diagnostics::write_line("LAYOUT_OK");
    }

    // Set the SIMD policy before we test helpers that may choose a scalar or SSE2 backend.
    let _ = simd::initialize_runtime_policy(
        entry::simd_force_no_cpuid_requested(),
        entry::simd_force_disable_requested(),
        entry::is_test_mode(),
    );

    if !string_helpers_are_sane() {
        return Err(EarlyInitFailure::StringHelpers);
    }

    if entry::is_test_mode() {
        diagnostics::write_line("STRING_HELPERS_OK");
    }

    if !memory_helpers_are_sane() {
        return Err(EarlyInitFailure::MemoryHelpers);
    }

    if entry::is_test_mode() {
        diagnostics::write_line("MEMORY_HELPERS_OK");
    }

    console::write_bytes(b"42");
    Ok(())
}

// Make sure `.bss` sits where we expect it to inside the overall kernel image.
fn layout_is_sane() -> bool {
    layout_order_is_sane(
        entry::kernel_range(),
        entry::bss_range(),
        entry::layout_override_requested(),
    )
}

fn string_helpers_are_sane() -> bool {
    if entry::string_override_requested() {
        return false;
    }

    // These are the bare minimum C-string checks we rely on early in boot.
    // `strlen` should stop at the first NUL and ignore anything after it.
    let empty = [0u8];
    let embedded = [b'o', b'k', 0, b'x', 0];

    if unsafe { string::strlen(empty.as_ptr()) } != 0 {
        return false;
    }

    if unsafe { string::strlen(embedded.as_ptr()) } != 2 {
        return false;
    }

    if entry::is_test_mode() {
        diagnostics::write_line("STRLEN_OK");
    }

    let equal = *b"42\0";
    let prefix = *b"ab\0";
    let longer = *b"abc\0";
    let high_lhs = [0x80, 0];
    let high_rhs = [0x7f, 0];

    // `strcmp` should handle the usual trouble spots: same string, prefix ordering, and bytes
    // with the high bit set.
    if unsafe { string::strcmp(equal.as_ptr(), equal.as_ptr()) } != 0 {
        return false;
    }

    if unsafe { string::strcmp(prefix.as_ptr(), longer.as_ptr()) } >= 0 {
        return false;
    }

    if unsafe { string::strcmp(high_lhs.as_ptr(), high_rhs.as_ptr()) } <= 0 {
        return false;
    }

    if entry::is_test_mode() {
        diagnostics::write_line("STRCMP_OK");
    }

    true
}

fn memory_helpers_are_sane() -> bool {
    if entry::memory_override_requested() {
        return false;
    }

    // These buffers keep known bytes on both sides so off-by-one writes are easy to catch.
    // `memcpy` should return the destination pointer and touch only the requested window.
    let src = [1u8, 2u8, 3u8];
    let mut dst = [0xAAu8, 0xBBu8, 0xCCu8, 0xDDu8, 0xEEu8];
    let copy_dst = unsafe { dst.as_mut_ptr().add(1) };
    let copy_return = unsafe { memory::memcpy(copy_dst, src.as_ptr(), src.len()) };

    if copy_return != copy_dst {
        return false;
    }

    if dst != [0xAAu8, 1u8, 2u8, 3u8, 0xEEu8] {
        return false;
    }

    if entry::is_test_mode() {
        emit_memcpy_backend_marker(memory::memcpy_backend());
        diagnostics::write_line("MEMCPY_OK");
    }

    // `memset` gets the same treatment: right return value, right bytes changed, guard bytes left
    // alone.
    let mut fill = [0x11u8, 0x22u8, 0x33u8, 0x44u8, 0x55u8];
    let fill_dst = unsafe { fill.as_mut_ptr().add(1) };
    let fill_return = unsafe { memory::memset(fill_dst, 0x99u8, 3) };

    if fill_return != fill_dst {
        return false;
    }

    if fill != [0x11u8, 0x99u8, 0x99u8, 0x99u8, 0x55u8] {
        return false;
    }

    if entry::is_test_mode() {
        emit_memset_backend_marker(memory::memset_backend());
        diagnostics::write_line("MEMSET_OK");
    }

    true
}

// Show which backend won at runtime so the test log tells the whole story.
fn emit_memcpy_backend_marker(backend: MemoryBackend) {
    match backend {
        MemoryBackend::Scalar => diagnostics::write_line("MEMCPY_BACKEND_SCALAR"),
        MemoryBackend::Sse2 => diagnostics::write_line("MEMCPY_BACKEND_SSE2"),
    }
}

fn emit_memset_backend_marker(backend: MemoryBackend) {
    match backend {
        MemoryBackend::Scalar => diagnostics::write_line("MEMSET_BACKEND_SCALAR"),
        MemoryBackend::Sse2 => diagnostics::write_line("MEMSET_BACKEND_SSE2"),
    }
}
