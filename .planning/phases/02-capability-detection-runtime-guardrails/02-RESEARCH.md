# Phase 2 Research: Capability Detection & Runtime Guardrails

## Evidence From Current Code

### Early-init sequencing

- [`src/kernel/core/entry.rs`](/home/motero/Code/kfs-1/src/kernel/core/entry.rs) owns `kmain()` and routes test-mode failures through marker-driven diagnostics.
- [`src/kernel/core/init.rs`](/home/motero/Code/kfs-1/src/kernel/core/init.rs) performs the ordered early-init checks and already emits runtime markers such as `BSS_OK`, `LAYOUT_OK`, `STRING_HELPERS_OK`, and `MEMORY_HELPERS_OK`.

### Current arch test hook surface

- [`src/arch/i386/runtime_io.asm`](/home/motero/Code/kfs-1/src/arch/i386/runtime_io.asm) already exports test-oriented arch helpers like `kfs_arch_should_fail_layout` and `kfs_arch_should_fail_memory`.
- [`Makefile`](/home/motero/Code/kfs-1/Makefile) already threads `KFS_TEST_*` flags into NASM defines for runtime-negative cases.

### Architecture gates that shape the design

- [`scripts/architecture-tests/layer-dependencies.sh`](/home/motero/Code/kfs-1/scripts/architecture-tests/layer-dependencies.sh) forbids `core` importing `machine` directly and forbids `klib` importing `machine` or `services`.
- [`scripts/architecture-tests/runtime-ownership.sh`](/home/motero/Code/kfs-1/scripts/architecture-tests/runtime-ownership.sh) currently proves `start -> kmain -> core init -> services -> drivers`.
- [`docs/simd_policy.md`](/home/motero/Code/kfs-1/docs/simd_policy.md) says future SIMD work should keep typed low-level machine primitives in `machine`, runtime-policy sequencing in `core`, and helper dispatch in `klib`.

### Existing helper boundary

- [`src/kernel/klib/memory/mod.rs`](/home/motero/Code/kfs-1/src/kernel/klib/memory/mod.rs) and [`src/kernel/klib/memory/imp.rs`](/home/motero/Code/kfs-1/src/kernel/klib/memory/imp.rs) currently expose scalar-only `memcpy`/`memset`.
- Host semantics for those helpers are already covered by [`tests/host_memory.rs`](/home/motero/Code/kfs-1/tests/host_memory.rs).

## Design Conclusions

### 1. Raw feature detection should live in `machine`

Phase 2 needs a typed abstraction for:
- CPUID availability
- detected MMX/SSE/SSE2 capability bits

That belongs in `src/kernel/machine/cpu.rs`, not in `core` or `services`, because it is a typed low-level machine concern.

### 2. Core still needs a service seam

Because the current layer gates reject `core -> machine`, early-init should call a service-owned initialization entry point such as:
- `services::simd::initialize_runtime_policy()`

That service can depend on:
- `machine::cpu` for detection
- `klib::simd` for policy installation
- `services::diagnostics` for test-mode markers

### 3. Klib needs policy state even before acceleration exists

Future helper code cannot import `services` or `machine`, so Phase 2 should establish:
- `klib::simd::RuntimePolicy`
- query functions for `mmx_allowed()`, `sse_allowed()`, `sse2_allowed()`
- installation/reset helpers usable by early init and host tests

The important guardrail is that Phase 2 policy remains scalar-only even when hardware capability is detected, because Phase 3 has not yet enabled execution legality.

### 4. Runtime tests should use deterministic arch overrides

Default host/QEMU CPU capabilities are not stable enough to make all runtime tests deterministic.

Use the existing `runtime_io.asm` pattern plus `Makefile` test env flags for:
- forced `no cpuid`
- forced `disable simd`

That allows runtime markers and rejection cases to be deterministic without depending on the real CPU model.

## Risks To Carry Into Planning

- `core -> machine` remains blocked by existing architecture tests, so any direct import approach will fail both policy and tests.
- CPUID detection must compile under the host-linked library root as well as the freestanding target.
- Phase 2 must not accidentally make the stability test `freestanding-simd.sh` obsolete; execution must remain scalar-only.
