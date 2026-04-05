# Architecture

**Analysis Date:** 2026-04-05

## Pattern Overview

**Overall:** Layered monolithic freestanding kernel with dual Rust crate roots

**Key Characteristics:**
- One final kernel image linked from Rust and x86 assembly objects
- Two intentional Rust crate roots: `src/main.rs` for the freestanding kernel and `src/lib.rs` for host-linked tests
- One shared subsystem tree rooted at `src/kernel/mod.rs`
- Tests enforce architecture, export ownership, and freestanding artifact properties with shell scripts

## Layers

**arch:**
- Purpose: unavoidable x86 entry/runtime helpers and linker-visible assembly edges
- Contains: `src/arch/i386/boot.asm`, `src/arch/i386/runtime_io.asm`, `src/arch/i386/linker.ld`
- Depends on: low-level x86 calling/boot conventions
- Used by: freestanding kernel entry and test harnesses

**freestanding:**
- Purpose: Rust-only freestanding policy that should not leak into host tests
- Contains: `src/freestanding/panic.rs`, `src/freestanding/section_markers.rs`
- Depends on: core-only Rust runtime items
- Used by: `src/main.rs`

**kernel/core:**
- Purpose: entry handoff and early runtime sequencing
- Contains: `src/kernel/core/entry.rs`, `src/kernel/core/init.rs`
- Depends on: services, types, linker-visible arch helpers
- Used by: boot path through `kmain`

**kernel/services:**
- Purpose: kernel-facing console and diagnostics surfaces
- Contains: `src/kernel/services/console.rs`, `src/kernel/services/diagnostics.rs`
- Depends on: drivers and types
- Used by: core init and runtime flows

**kernel/drivers:**
- Purpose: device-facing behavior for VGA text, serial, and keyboard handling
- Contains: `src/kernel/drivers/vga_text/**`, `src/kernel/drivers/serial/mod.rs`, `src/kernel/drivers/keyboard/**`
- Depends on: machine primitives and types
- Used by: services

**kernel/machine:**
- Purpose: typed low-level machine primitives
- Contains: `src/kernel/machine/port.rs`
- Depends on: inline asm and x86 port semantics
- Used by: drivers

**kernel/klib and kernel/types:**
- Purpose: freestanding helper routines and fixed-layout semantic types
- Contains: `src/kernel/klib/{memory,string}/**`, `src/kernel/types/**`
- Depends on: `core`
- Used by: multiple kernel layers and host tests

## Data Flow

**Boot Flow:**
1. GRUB loads the kernel image and jumps to `start` in `src/arch/i386/boot.asm`
2. Assembly sets the stack and calls `kmain`
3. `src/kernel/core/entry.rs` runs early-init sequencing from `src/kernel/core/init.rs`
4. Diagnostics and console services drive serial/VGA output
5. The kernel enters the current long-running console/keyboard flow

**Host Test Flow:**
1. Host `#[test]` binaries link the `kfs` library root from `src/lib.rs`
2. Tests import production APIs through `kfs::kernel::...`
3. Shell harnesses call `make test` or narrower script entry points

**State Management:**
- No heap allocator is present in the analyzed kernel path
- Global state is minimized; hardware state and linker-visible markers are explicit

## Key Abstractions

**Dual crate-root boundary:**
- Purpose: keep freestanding policy out of host test binaries while sharing production modules
- Examples: `src/main.rs`, `src/lib.rs`, `src/kernel/mod.rs`
- Pattern: one shared module tree with two sanctioned roots

**Typed machine primitive:**
- Purpose: isolate raw x86 port I/O
- Examples: `Port` in `src/kernel/machine/port.rs`
- Pattern: tiny primitive wrapped by higher-level drivers

**Service-over-driver runtime path:**
- Purpose: keep console/diagnostics above device logic
- Examples: `src/kernel/services/console.rs`, `src/kernel/drivers/vga_text/writer.rs`
- Pattern: service orchestration over driver leaf behavior

## Entry Points

**Freestanding kernel root:**
- Location: `src/main.rs`
- Triggers: kernel build from `Makefile`
- Responsibilities: crate-level `no_std`/`no_main` policy and module wiring

**Host test library root:**
- Location: `src/lib.rs`
- Triggers: host Rust tests
- Responsibilities: expose shared kernel modules without freestanding-only policy

**Assembly entry:**
- Location: `src/arch/i386/boot.asm`
- Triggers: GRUB boot handoff
- Responsibilities: set initial machine state and call `kmain`

## Error Handling

**Strategy:** fail fast in freestanding mode; use explicit runtime markers in tests

**Patterns:**
- panic converges to halt through `src/freestanding/panic.rs`
- early-init failures route through marker-driven diagnostics and test exits
- shell harnesses treat textual/serial markers as proof points

## Cross-Cutting Concerns

**Architecture enforcement:**
- Shell tests under `scripts/architecture-tests/` and `scripts/rejection-tests/` guard module ownership, exports, and forbidden bypasses

**Freestanding proof:**
- `make test` includes artifact inspection for static/freestanding properties plus QEMU boot/runtime checks

**Documentation discipline:**
- `AGENTS.md` and repo docs explicitly require path/ownership docs to move with implementation changes

---
*Architecture analysis: 2026-04-05*
*Update when major patterns change*
