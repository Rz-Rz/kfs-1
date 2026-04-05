# KFS-1 Kernel Architecture

Purpose:
- describe the architecture that the repository implements now
- define the current ownership contract for kernel code
- define the current build, ABI, and runtime boundaries
- define which rules are enforced by tests

This document is a current-state contract.
It is not a historical analysis.

## 1. Subject constraints

Subject requirements that matter to architecture:
- the subject requires a 32-bit x86 kernel environment ("i386 (x86)" in the subject wording)
- GRUB boots the kernel
- the project provides ASM boot code and kernel code in the chosen language
- the kernel must link without host runtime dependencies
- the kernel must provide basic helper code and basic types
- the kernel must write characters to the screen and display `42`

Subject requirements that do not exist:
- no required internal layer structure
- no required Rust-owned serial stack
- no required driver/service split beyond whatever is needed to stay clean and extensible

Source: [`docs/subject.pdf`](/home/motero/Code/kfs-1/docs/subject.pdf)

Current repo interpretation of that subject constraint:
- the final kernel artifact is ELF32 with machine `Intel 80386`
- the boot path and linker remain 32-bit x86 (`elf_i386`, multiboot, `qemu-system-i386`)
- the Rust codegen baseline currently uses `i586-unknown-linux-gnu`

Why the Rust baseline is `i586` instead of `i686`:
- the stable Rust `i686-unknown-linux-gnu` target now carries an SSE2-based ABI contract
- this repo currently keeps freestanding kernel artifacts free of SSE/XMM instructions
- using `i686` while forcing `-sse2` is being phased into a hard compiler error

Current limitation:
- this means the repo currently implements the subject's 32-bit x86 requirement with an ELF/i386 binary format and boot path, but not with a literal 80386 Rust codegen baseline
- if the course is later interpreted to require strict 80386 instruction compatibility rather than generic 32-bit x86, this choice must be revisited explicitly

## 2. Current architecture decision

The repo implements a layered monolithic kernel.

Meaning:
- boot code, drivers, services, helpers, and core sequencing all remain in one kernel image
- internal boundaries are expressed primarily through Rust modules and filesystem ownership
- only true low-level edges use ABI boundaries

The active first-level ownership domains under `src/kernel/` are:
- `core`
- `drivers`
- `klib`
- `machine`
- `services`
- `types`

Those are the only allowed first-level kernel domains.

## 3. Build roots

The repo has two crate roots, one canonical shared module root, and one freestanding-only support root:

1. Kernel binary root
- [`src/main.rs`](/home/motero/Code/kfs-1/src/main.rs)
- compiled by the kernel build
- owns only freestanding crate policy and section-marker wiring
- exposes the canonical shared tree as `crate::kernel`

2. Shared kernel module root
- [`src/kernel/mod.rs`](/home/motero/Code/kfs-1/src/kernel/mod.rs)
- owns the shared subsystem map
- is the only canonical root for `core`, `drivers`, `klib`, `machine`, `services`, and `types`

3. Freestanding-only support root
- [`src/freestanding/mod.rs`](/home/motero/Code/kfs-1/src/freestanding/mod.rs)
- owns freestanding-only support code that must not be part of the shared host-linked tree
- currently owns panic convergence and section-marker symbols

4. Host/library root
- [`src/lib.rs`](/home/motero/Code/kfs-1/src/lib.rs)
- exposes the same shared production module tree for host-side tests
- intentionally excludes freestanding root policy

Current build rule:
- [`Makefile`](/home/motero/Code/kfs-1/Makefile) compiles the kernel from `src/main.rs`
- the kernel emits one Rust object: `build/arch/<arch>/rust/kernel.o`
- the repo does not compile peer `src/kernel/*.rs` files as separate Rust objects

## 4. Ownership map

### 4.1 Layer responsibilities

| Layer | Owns | Must not own |
|---|---|---|
| `core` | entry handoff and early-init sequencing | raw hardware implementation, driver internals, freestanding-only panic/lang items |
| `services` | kernel-facing APIs above drivers | raw MMIO, raw port I/O, boot sequencing |
| `drivers` | hardware behavior and device-facing writer state | boot policy, panic policy |
| `klib` | freestanding helper families | device logic, runtime sequencing |
| `machine` | typed low-level machine primitives | service policy, boot policy |
| `types` | semantic shared data and fixed-layout shared structs | I/O, linker-visible ABI exports, orchestration |
| `freestanding` | panic handler and freestanding-only section markers | shared host-linked module logic |

### 4.2 Current file owners

| File | Owner | Responsibility |
|---|---|---|
| [`src/kernel/core/entry.rs`](/home/motero/Code/kfs-1/src/kernel/core/entry.rs) | `core` | `kmain`, arch handoff wrappers |
| [`src/kernel/core/init.rs`](/home/motero/Code/kfs-1/src/kernel/core/init.rs) | `core` | early-init sequence and sanity checks |
| [`src/freestanding/panic.rs`](/home/motero/Code/kfs-1/src/freestanding/panic.rs) | `freestanding` | panic convergence to halt path |
| [`src/kernel/services/console.rs`](/home/motero/Code/kfs-1/src/kernel/services/console.rs) | `services` | console service surface |
| [`src/kernel/services/diagnostics.rs`](/home/motero/Code/kfs-1/src/kernel/services/diagnostics.rs) | `services` | runtime diagnostics output surface |
| [`src/kernel/drivers/serial/mod.rs`](/home/motero/Code/kfs-1/src/kernel/drivers/serial/mod.rs) | `drivers` | serial driver facade built on `machine::Port` |
| [`src/kernel/drivers/vga_text/mod.rs`](/home/motero/Code/kfs-1/src/kernel/drivers/vga_text/mod.rs) | `drivers` | VGA text driver facade and cell encoding |
| [`src/kernel/drivers/vga_text/writer.rs`](/home/motero/Code/kfs-1/src/kernel/drivers/vga_text/writer.rs) | `drivers` | raw VGA writer mechanics |
| [`src/kernel/klib/string/mod.rs`](/home/motero/Code/kfs-1/src/kernel/klib/string/mod.rs) | `klib` | string helper ABI facade |
| [`src/kernel/klib/string/imp.rs`](/home/motero/Code/kfs-1/src/kernel/klib/string/imp.rs) | `klib` | private string helper implementation |
| [`src/kernel/klib/memory/mod.rs`](/home/motero/Code/kfs-1/src/kernel/klib/memory/mod.rs) | `klib` | memory helper ABI facade |
| [`src/kernel/klib/memory/imp.rs`](/home/motero/Code/kfs-1/src/kernel/klib/memory/imp.rs) | `klib` | private memory helper implementation |
| [`src/kernel/machine/port.rs`](/home/motero/Code/kfs-1/src/kernel/machine/port.rs) | `machine` | `Port` typed primitive |
| [`src/kernel/types/range.rs`](/home/motero/Code/kfs-1/src/kernel/types/range.rs) | `types` | `KernelRange` and layout-order helper |
| [`src/kernel/types/screen.rs`](/home/motero/Code/kfs-1/src/kernel/types/screen.rs) | `types` | screen-domain shared types and constants |

## 5. Runtime path

The current runtime path is:

`start`
-> `kmain`
-> `kernel::core::init::run_early_init`
-> `kernel::services::diagnostics`
-> `kernel::drivers::serial`
-> `kernel::machine::Port`
and independently
-> `kernel::services::console`
-> `kernel::drivers::vga_text`
-> `kernel::drivers::vga_text::writer`

Concrete locations:
- the boot entry symbol `start` lives in [`src/arch/i386/boot.asm`](/home/motero/Code/kfs-1/src/arch/i386/boot.asm)
- `kmain` lives in [`src/kernel/core/entry.rs`](/home/motero/Code/kfs-1/src/kernel/core/entry.rs)
- the console service lives in [`src/kernel/services/console.rs`](/home/motero/Code/kfs-1/src/kernel/services/console.rs)
- the VGA hardware leaf lives in [`src/kernel/drivers/vga_text/writer.rs`](/home/motero/Code/kfs-1/src/kernel/drivers/vga_text/writer.rs)
- panic convergence lives in [`src/freestanding/panic.rs`](/home/motero/Code/kfs-1/src/freestanding/panic.rs)

Important naming detail:
- the filesystem layer is `src/kernel/core/`
- the crate module path is `crate::kernel::core::...`
- the path is namespaced under `kernel`, so no separate crate-level alias is needed

## 6. ABI contract

### 6.1 True external ABI edges

These are the real low-level boundaries in the repo:
- ASM boot to Rust entry
- linker-defined section/layout symbols to Rust
- arch runtime helpers exposed from assembly to Rust

### 6.2 Callable Rust ABI exports

The current callable Rust ABI surface is:
- `kmain`
- `kfs_strlen`
- `kfs_strcmp`
- `kfs_memcpy`
- `kfs_memset`

Owners:
- [`src/kernel/core/entry.rs`](/home/motero/Code/kfs-1/src/kernel/core/entry.rs) owns `kmain`
- [`src/kernel/klib/string/mod.rs`](/home/motero/Code/kfs-1/src/kernel/klib/string/mod.rs) owns `kfs_strlen` and `kfs_strcmp`
- [`src/kernel/klib/memory/mod.rs`](/home/motero/Code/kfs-1/src/kernel/klib/memory/mod.rs) owns `kfs_memcpy` and `kfs_memset`

The following layers must not export linker-visible Rust symbols:
- `services`
- `types`
- `drivers`
- non-entry `core`
- private leaf files

The final binary also intentionally retains non-callable global support symbols for:
- boot entry and linker layout (`start`, `kernel_start`, `kernel_end`, `bss_start`, `bss_end`)
- arch runtime helpers (`kfs_arch_*`)
- section/layout proof markers in [`src/freestanding/section_markers.rs`](/home/motero/Code/kfs-1/src/freestanding/section_markers.rs)

## 7. Current type contract

Required current architecture types:

| Type | Owner | Representation |
|---|---|---|
| `Port` | `machine/port.rs` | `#[repr(transparent)]` |
| `KernelRange` | `types/range.rs` | `#[repr(C)]` |
| `ColorCode` | `types/screen.rs` | `#[repr(transparent)]` |
| `ScreenCell` | `types/screen.rs` | `#[repr(C)]` |
| `CursorPos` | `types/screen.rs` | `#[repr(C)]` |

Also present:
- `ScreenDimensions`
- `ScreenPosition`
- `VGA_TEXT_DIMENSIONS`

## 8. Current hardware-access contract

Current hardware ownership:
- direct VGA MMIO and volatile writes belong in `drivers`
- raw assembly entry/runtime helpers stay in `arch`
- typed port I/O inline assembly belongs in `machine`
- linker symbols stay at the `arch`/entry boundary

Current serial reality:
- serial driver register access is owned by [`src/kernel/drivers/serial/mod.rs`](/home/motero/Code/kfs-1/src/kernel/drivers/serial/mod.rs)
- the serial driver uses [`src/kernel/machine/port.rs`](/home/motero/Code/kfs-1/src/kernel/machine/port.rs) for typed port ownership
- `arch` no longer owns serial init/write behavior
- `arch` still owns only the unavoidable assembly/runtime helpers such as `start`, halt, qemu exit, and test-flag toggles

This is intentional current-state documentation, not a future promise.

## 9. Host-test contract

Host tests must exercise the production module layout, not a parallel test-only tree.

Current rule:
- host unit tests import the production API through the `kfs::kernel::...` path family exposed by [`src/lib.rs`](/home/motero/Code/kfs-1/src/lib.rs)
- host tests do not `include!` or `#[path]`-mount private production leaf files directly

Examples:
- [`tests/host_layout_and_vga_cell.rs`](/home/motero/Code/kfs-1/tests/host_layout_and_vga_cell.rs)
- [`tests/host_string.rs`](/home/motero/Code/kfs-1/tests/host_string.rs)
- [`tests/host_memory.rs`](/home/motero/Code/kfs-1/tests/host_memory.rs)
- [`tests/host_types.rs`](/home/motero/Code/kfs-1/tests/host_types.rs)

## 10. Enforced rules

The repo enforces the architecture through:
- canonical-root and allowed-domain checks
- private-leaf locality and anti-bypass checks
- layer-dependency checks
- export-ownership checks
- type-contract checks
- runtime-ownership checks
- rejection tests
- boot/runtime tests

The architecture suite intentionally treats only these filesystem facts as hard structural contract:
- the canonical crate and shared-module roots
- the allowed first-level ownership domains under `src/kernel/`
- the single shared `src/kernel/mod.rs` top-level root

It does not treat every current deep leaf filename as permanent architecture law.

Relevant suites:
- [`scripts/architecture-tests/`](/home/motero/Code/kfs-1/scripts/architecture-tests)
- [`scripts/rejection-tests/`](/home/motero/Code/kfs-1/scripts/rejection-tests)
- [`scripts/boot-tests/`](/home/motero/Code/kfs-1/scripts/boot-tests)
- [`scripts/tests/unit/`](/home/motero/Code/kfs-1/scripts/tests/unit)

The hard gate is:
- `make test`

## 11. Placement rules

Use these rules when adding new code:

- If the code decides boot order or early-init flow, it belongs in `core`.
- If the code is a panic handler, lang item, or freestanding-only linker/section support, it belongs in `freestanding`, not in the shared `kernel` tree.
- If the code exposes a capability the rest of the kernel should call, it belongs in `services`.
- If the code knows concrete hardware behavior or writes to device memory/registers, it belongs in `drivers`.
- If the code is a freestanding reusable helper family, it belongs in `klib`.
- If the code gives a typed meaning to machine-local primitives, it belongs in `machine`.
- If the code defines shared semantic data or fixed-layout shared structs, it belongs in `types`.

## 12. Current non-goals

These are not part of the current architecture contract:
- forcing all low-level runtime I/O through `machine::Port`
- a public host-testing surface for `core::entry`
- compatibility layers for removed file layouts

If those become requirements, this document should be updated after the implementation changes land.
