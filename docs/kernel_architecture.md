# KFS-1 Kernel Architecture Proposal


Purpose:
- describe what architecture the repo is using now
- explain why the current boundary model is inconsistent
- compare recognized kernel architecture families and internal module organizations
- choose one target architecture for the whole KFS progression
- define enforceable dependency rules so later features do not invent a new structure each time

---

## 1. Subject basis

Subject-mandated obligations relevant to architecture:
- the project is an i386 kernel
- GRUB initializes and transfers control to the kernel
- the kernel contains boot code, linker control, chosen-language kernel code, helper functions, and a screen interface
- the Makefile must compile all source files with the correct flags and produce a bootable image
- the project later grows into cursor, scrolling, colors, printing helpers, keyboard echo, and multiple screens

The architecture is not specified by the subject:
- how internal kernel modules are organized
- where ABI boundaries exist
- whether helpers, drivers, and orchestration live in one layer or several
- whether Rust-to-Rust subsystem calls should use source/module boundaries or binary/ABI-style boundaries


Primary sources:
- `docs/subject.pdf`
- `docs/kfs1_epics_features.md`
- `docs/kfs1_repo_status.md`
- `Makefile`

External sources:
- OSDev kernel-family pages
- Phil Opp's subsystem design examples
- Linux internal subsystem/driver-model documentation

---

## 2. Current repo status
Added basic vga writer & used it in kmain + added test for vga writer… 


### 2.1 Present status

- ASM boot/linker artifacts live under `src/arch/i386/`
- Rust kernel sources live under `src/kernel/`
- the current kernel entrypoint is `src/kernel/kmain.rs`
- helper families exist as top-level Rust files:
  - `src/kernel/string.rs`
  - `src/kernel/memory.rs`
  - `src/kernel/vga.rs`
- shared semantic types exist in:
  - `src/kernel/types.rs`
  - `src/kernel/types/port.rs`
  - `src/kernel/types/range.rs`
- private implementation files already exist for some families:
  - `src/kernel/string/string_impl.rs`
  - `src/kernel/memory/memory_impl.rs`
  - `src/kernel/kmain/logic_impl.rs`

- `Makefile` compiles every top-level `src/kernel/*.rs` file independently into an object file:
  - `rust_source_files := $(wildcard src/rust/*.rs) $(filter-out src/kernel/types.rs,$(wildcard src/kernel/*.rs))`
- those objects are then linked together with `ld`

- some Rust-to-Rust boundaries are expressed as C ABI-style exported symbols:
  - `kfs_strlen`
  - `kfs_strcmp`
  - `kfs_memcpy`
  - `kfs_memset`
  - `vga_init`
  - `vga_putc`
  - `vga_puts`

- other boundaries are pure source inclusion:
  - `types.rs`
  - `*_impl.rs`

- `kmain` currently owns runtime orchestration and also directly depends on low-level helper and device-facing surfaces

### 2.2 What architecture that implies today

The repo is not using one architecture. It is using several at once.

| Concern | Current repo pattern | Implication |
|---|---|---|
| ASM to Rust entry | true ABI boundary | expected and correct |
| Linker symbols to Rust | true ABI boundary | expected and correct |
| Shared helper internals | source inclusion | normal private implementation pattern |
| Top-level kernel features | separate linked object files | pseudo-component model |
| Rust-to-Rust feature calls | often `extern "C"` | fake internal ABI |
| `kmain` ownership | orchestration plus subsystem knowledge | weak separation |

### 2.3 Architectural smells in the current repo

- there is no single answer to "what is a kernel module in this repo?"
- some top-level Rust files behave like independent linked components
- some internal files behave like normal source modules
- some internal Rust boundaries use ABI symbols even though they are not true external boundaries
- `kmain` still knows details that should eventually belong to subsystem-specific layers

---

**The repo currently mixes at least three boundary styles that do not describe one shared architecture.**

This is the key point: these styles encode different answers to the same question, "how do kernel parts relate to each other?"
Because all three are active at once, the repo does not currently have a single internal architecture.

---

### Source inclusion

Example:

```rust
// src/kernel/types.rs
#[path = "types/port.rs"]
mod port;
#[path = "types/range.rs"]
mod range;

pub use self::port::Port;
pub use self::range::KernelRange;
```

```rust
// src/kernel/string.rs
#[path = "string/string_impl.rs"]
mod string_impl;
use string_impl::{string_cmp_impl, string_len_impl};
```

Reason to change:
- this pattern is valid for private internals on its own
- it assumes one coherent Rust module tree with source-level ownership
- it conflicts with the repo's other active model where top-level files are treated as separately linked components
- therefore, source inclusion itself is not a problem; using it beside incompatible boundary models without one rule is the bug

---

### Link-time component separation

Example:

```makefile
# Makefile
rust_source_files := $(wildcard src/rust/*.rs) \
  $(filter-out src/kernel/types.rs, $(wildcard src/kernel/*.rs))

rust_object_files := $(patsubst src/%.rs, \
  build/arch/$(arch)/rust/%.o, $(rust_source_files))

build/arch/$(arch)/rust/%.o: src/%.rs
	rustc --crate-type lib --emit=obj ... -o $@ $<
```

```makefile
$(kernel): $(assembly_object_files) $(rust_object_files) $(linker_script)
	ld -m elf_i386 -n -T $(linker_script) -o $(kernel) \
	    $(assembly_object_files) $(rust_object_files)
```

Why to keep/change:
- this pattern turns file placement into an architectural decision (`src/kernel/*.rs` becomes "component-like")
- there is no explicit subsystem contract attached to that decision (no module tree contract, no declared facade rule)
- `types.rs` being excluded proves this is not a consistent architecture rule, but a build-time special case
- result: adding a new file changes structure mechanically via Makefile globbing, not by architecture intent

---

### ABI-style symbol boundaries

Exammple:

```rust
// src/kernel/string.rs
#[no_mangle]
pub unsafe extern "C" fn kfs_strlen(ptr: *const u8) -> usize { ... }
```

```rust
// src/kernel/vga.rs
#[no_mangle]
pub extern "C" fn vga_init() { ... }
#[no_mangle]
pub extern "C" fn vga_puts(text: *const u8) { ... }
```

```rust
// src/kernel/kmain.rs
unsafe extern "C" {
  static kernel_start: u8;      // ABI edge: linker symbol
  static kfs_test_mode: u8;     // ABI edge: asm symbol
  fn vga_init();                // Rust-to-Rust call via C ABI
  fn kfs_strlen(ptr: *const u8) -> usize; // Rust-to-Rust call via C ABI
}
```

```asm
; src/arch/i386/boot.asm
extern kmain
call kmain
```

Reason to change/keep:
- true ABI edges (ASM/linker) are required and correct
- internal Rust-to-Rust calls using the same ABI mechanism are an accidental boundary choice in this repo
- mixing both in one import surface hides which boundaries are truly external versus internal
- result: internal subsystem boundaries become C-ABI-shaped instead of architecture-shaped

---

### Why this is architecturally incorrect

This file's architecture target is a layered monolithic kernel with clear subsystem ownership.
The current mixed boundary model violates that target in concrete ways:

| Required architectural question | Current repo answers | Result |
|---|---|---|
| "What is a kernel module?" | sometimes an included source file, sometimes a separately linked file, sometimes an ABI symbol group | no single module definition |
| "How should one Rust subsystem call another?" | sometimes direct module use, sometimes linker symbol, sometimes `extern "C"` | no consistent internal call contract |
| "Which ABI edges are truly external?" | mixed in one `extern "C"` import surface | accidental ABI hardening of internals |
| "Where does a new feature file belong?" | determined by Makefile glob + symbol export habit | mechanical placement, not architectural placement |

In short: the repo is not choosing between architecture options; it is running multiple incompatible boundary contracts at once.

---

## 3. Architecture defintion

- what counts as a kernel subsystem
- what counts as a private implementation detail
- where ABI boundaries are real and where they are accidental
- where shared semantic types belong
- whether `kmain` is an orchestrator or a place where feature logic accumulates
- what architecture can scale through the later subject work without each feature choosing a different pattern

The rest of this document tries to answer that question with explicit alternatives and a final decision.

---

## 4. Architecture comparison matrix

### 4.1 Kernel-family comparison

We tried to build a benchkmark of different well-known kernel architectures ( to the best of my efforts and knowledge).
This is the high-level family comparison from OSDev-style architecture choices.

| Architecture family | Description | Internal boundary style | Strengths | Weaknesses | Long-term growth | Fit 
|---|---|---|---|---|---|---|
| Flat monolith | one kernel with little separation | almost none | fastest bring-up | becomes tangled quickly | poor | poor |
| Monolithic kernel | one kernel with internal subsystems | source/module boundaries | simple, efficient, common hobby-kernel path | needs discipline | strong | strong |
| Modular monolith | monolithic kernel with loadable/runtime modules | internal APIs plus possible runtime symbol interfaces | future extensibility | more loader/API complexity | strong | too heavy as a first commitment |
| Hybrid kernel | mixed model with selective decomposition | mixed | flexible in theory | often vague in practice | medium | weak fit here |
| Microkernel | minimal kernel, services moved out | process/IPC boundaries | strong isolation | high complexity and early design burden | high in theory | poor for this project stage |

Architecture-family conclusion:
- a monolithic kernel is the right base family
- a microkernel or hybrid design adds complexity too early
- a modular kernel is a later optional refinement, not the starting commitment

### 4.2 Internal organization comparison

This is the more important comparison for this repo.

| Internal organization | What it means | Current repo similarity | Growth behavior | Refactor pressure later | Architectural clarity |
|---|---|---|---|---|---|
| Ad hoc per-feature layout | each feature chooses its own file/boundary model | high | bad | extreme | poor |
| File-per-feature linked components | each top-level file is a pseudo-component | high | medium | high | medium-low |
| Layered monolith | one kernel with clear source layers | low | strong | low | strong |
| Layered monolith with subsystem facades | one kernel, plus stable service/driver separation | low | strongest | lowest | strongest |

### 4.3 ABI-boundary comparison

This comparison is about binary ABI usage, not about whether the kernel should have explicit contracts.
The real decision for this repo is not "ABI or no structure". The real decision is whether internal ABI use is absent, universal, ad hoc, or deliberately limited to specific kernel surface files.

| ABI strategy | Meaning | Benefit | Cost | Recommended? |
|---|---|---|---|---|
| No internal kernel ABI | only ASM/linker/external edges use ABI; all kernel code talks through Rust module boundaries | simplest binary model | rejects stable low-level kernel symbol surfaces for helper/device entry families | no |
| ABI between all top-level Rust parts | every major Rust part is exposed as a C ABI surface | uniform rule | over-hardens typed/stateful subsystems and forces ABI-shaped signatures everywhere | no |
| Mixed ad hoc ABI | some Rust internals use ABI, some do not, with no file-role rule | local convenience only | maximum confusion and no architectural predictability | no |
| Stratified kernel ABI | true external edges use ABI; selected low-level kernel surface files also expose ABI; private implementation stays Rust-internal | stable low-level contracts without forcing ABI on every file | requires explicit file-role rules and enforcement | yes |

Visual examples for each ABI strategy:

`No internal kernel ABI`

```rust
// kmain.rs
use crate::kernel::string::string_len;
use crate::kernel::vga::puts;

puts(b"42\0".as_ptr());
let len = unsafe { string_len(b"ok\0".as_ptr()) };
```

Effect:
- all internal calls are plain Rust module calls
- there is no stable exported kernel symbol surface for helper/device families

`ABI between all top-level Rust parts`

```rust
// every top-level file exports ABI
#[no_mangle]
pub unsafe extern "C" fn kfs_strlen(ptr: *const u8) -> usize { ... }

#[no_mangle]
pub extern "C" fn vga_puts(text: *const u8) { ... }

#[no_mangle]
pub extern "C" fn port_outb(port: u16, value: u8) { ... }
```

Effect:
- uniform binary boundary rule
- even typed/stateful internals get flattened into ABI-shaped signatures

`Mixed ad hoc ABI`

```rust
// kmain.rs
unsafe extern "C" {
    fn kfs_strlen(ptr: *const u8) -> usize;
}

use crate::kernel_types::Port;
use crate::kmain_logic::layout_order_is_sane;
```

Effect:
- one file calls some things through ABI, some through normal Rust modules
- the boundary model depends on file history, not architecture

`Stratified kernel ABI`

```rust
// stable ABI surface
#[no_mangle]
pub unsafe extern "C" fn kfs_strlen(ptr: *const u8) -> usize {
    unsafe { string_len(ptr) }
}

// private leaf implementation
pub unsafe fn string_len(ptr: *const u8) -> usize {
    unsafe { string_impl::string_len_impl(ptr) }
}
```

Effect:
- low-level kernel entry surfaces remain stable and callable through ABI
- private algorithms, typed helpers, and policy logic stay Rust-internal

Immediate consequence for this repo:
- This stays ABI:
  - `src/arch/i386/boot.asm -> kmain`
  - linker symbols such as `kernel_start`, `kernel_end`, `bss_start`, `bss_end` used from `src/kernel/kmain.rs`
  - `kmain.rs` importing `vga_init`, `vga_puts`, `kfs_strlen`, `kfs_strcmp`, `kfs_memcpy`, and `kfs_memset`
- This also stays ABI on purpose:
  - `src/kernel/string.rs` exporting `kfs_strlen` and `kfs_strcmp`
  - `src/kernel/memory.rs` exporting `kfs_memcpy` and `kfs_memset`
  - `src/kernel/vga.rs` exporting `vga_init`, `vga_putc`, and `vga_puts`
- This stays internal-only Rust:
  - `src/kernel/string/string_impl.rs` remains the private leaf for `kfs_strlen` and `kfs_strcmp`
  - `src/kernel/memory/memory_impl.rs` remains the private leaf for `kfs_memcpy` and `kfs_memset`
  - `src/kernel/kmain/logic_impl.rs` remains internal logic called through normal Rust use, not exported ABI
  - `src/kernel/types.rs` and `src/kernel/types/*` remain shared semantic types, not exported ABI surfaces
- Therefore this would be a violation under the chosen rule:
  - adding `#[no_mangle] pub extern "C"` exports inside `string_impl.rs`, `memory_impl.rs`, or `logic_impl.rs`
  - turning `types.rs` or `types/*` into symbol-export files just because another file wants to call them
  - creating a new top-level kernel file and exporting ABI from it without first designating it as a kernel ABI-surface file

### 4.4 Type and helper comparison


The fore ABI strategy decides which files are stable binary surfaces.
The type/helper model then decides what is allowed to cross those surfaces and what must stay behind them.

**If ABI is used everywhere:**
- more data tends to collapse into primitives, raw pointers, and flat signatures
- richer typed/stateful internals become harder to preserve cleanly

**If there is no internal ABI at all:**
- helpers and drivers can stay purely Rust-internal
- but you lose the stable low-level symbol surfaces that we alrady used and is requested by the subject, uses for helper/device entry files

**With the chosen stratified ABI model:**
- low-level ABI-surface files *should expose primitive or low-level signatures*
- *semantic types belong behind those surfaces* unless the type itself is a stable cross-subsystem concept
- helper families should have one stable public entry file and private leaf implementation files
- `types` should support internal correctness and meaning, not become a dumping ground for exported ABI wrappers

| Model | Shared types | Helper library | Driver structure | Result |
|---|---|---|---|---|
| Everything primitive | none | scattered | drivers leak details upward | weak semantics |
| Wrap everything | too many types | bloated | high ceremony | artificial architecture |
| Semantic shared types only | only stable domain concepts | dedicated `klib`/helper layer | drivers remain focused | best balance |

Visual examples:

`Everything primitive`

```rust
pub extern "C" fn console_write_at(row: usize, col: usize, color: u8, ptr: *const u8) { ... }
```

Problem:
- every caller manipulates raw positions/colors directly
- driver details leak upward immediately

`Wrap everything`

```rust
pub struct ScreenRow(usize);
pub struct ScreenCol(usize);
pub struct ScreenColor(u8);
pub struct ByteCount(usize);
pub struct PortOffset(u16);
```

Problem:
- many wrappers carry little domain value
- the architecture becomes ceremony-heavy instead of clearer

`Semantic shared types only`

```rust
pub struct KernelRange {
    pub start: usize,
    pub end: usize,
}

pub struct Port(u16);
```

Result:
- stable concepts get type meaning
- helper/device entry surfaces can still stay low-level where needed
- typed semantics stay behind or beside ABI surfaces instead of forcing every call to become raw

Wiht both this ABI exposure and type modelign decided, we observe that :
- `string.rs`, `memory.rs`, and `vga.rs` are ABI-surface files
- `string_impl.rs` and `memory_impl.rs` are private leaf implementations
- `types.rs` and `types/*` keep semantic concepts such as `Port` and `KernelRange`
- therefore shouldnt be exporting `Port` or `KernelRange` as ABI wrappers just because helper/device files use ABI
- therefore shouldnt be moving helper logic into `types` just because helper files and type files are both "low level"

**Type-systme recommendation**:
- shared types should exist only for stable domain concepts
- helper routines should live in a dedicated kernel-library layer
- hardware-facing logic should not leak directly into orchestration

---

## 5. Proposed architecture

### 5.1 Chosen architecture

**Proposion:**
- use a statically linked monolithic kernel
- organize it as layered Rust subsystems with a stratified kernel ABI model
- keep ABI only where the boundary is either:
  - a mandatory external/toolchain edge
  - a deliberately designated low-level kernel surface file
- keep nested leaf files, semantic type files, and richer policy/orchestration logic Rust-internal by default

Why:
- this fixes the current inconsistency where some files behave like ABI components, some behave like Rust modules, and the rule is not stated anywhere
- it preserves the low-level ABI surfaces that are already useful for helper/device entry families
- it avoids flattening every typed or stateful internal concern into primitive ABI signatures
- it gives one file-role rule that can be enforced mechanically instead of relying on per-file habit

Justifications:
- the subject requires a bootable monolithic kernel, helper families such as `strlen` / `strcmp`, and a screen interface
- OSDev monolithic-kernel guidance supports one kernel binary with internal subsystem ownership
- Phil Opp's VGA writer approach supports keeping stateful device logic encapsulated instead of spreading raw memory writes through `kmain`

Current-rule  *status-quo of the repo*:
- `src/arch/i386/*` and linker symbols remain true external/toolchain ABI edges
- `src/kernel/kmain.rs`, `src/kernel/string.rs`, `src/kernel/memory.rs`, and `src/kernel/vga.rs` are the current designated ABI-surface files
- `src/kernel/string/string_impl.rs`, `src/kernel/memory/memory_impl.rs`, `src/kernel/kmain/logic_impl.rs`, `src/kernel/types.rs`, and `src/kernel/types/*` are internal files and must not become exported ABI surfaces by default

Before and after:
- before: adding a file under `src/kernel/` could accidentally create a pseudo-component because the Makefile, symbol exports, and direct source inclusion all implied different boundary rules
- after: a new file is internal by default unless it is explicitly designated as an ABI-surface file by architecture rule
- before: `kmain.rs` mixed linker symbols, ASM flags, helper ABI calls, and direct Rust module use without one stated reason
- after: `kmain.rs` is allowed to import designated low-level ABI surfaces while typed helpers and leaf logic stay behind normal Rust boundaries

### 5.2 Layer model

The proposed architecture has six kernel layers plus one cross-cutting ABI rule.

| Layer | Role | Owns | May depend on | Must not depend on |
|---|---|---|---|---|
| `arch` | architecture-specific bootstrap and machine entry | boot ASM, linker hooks, interrupt entry stubs, raw CPU/port instructions | none | upper layers |
| `machine` | typed machine primitives | port I/O wrappers, architecture-local low-level wrappers | `arch` | services/core policy |
| `types` | shared semantic data types | kernel ranges, screen positions, color codes, later address types | none or `machine` | policy logic |
| `klib` | freestanding helper library | memory/string/basic utility routines | `types` | device policy and orchestration |
| `drivers` | hardware-specific implementations | VGA text, serial, keyboard, later PIC/IDT helpers as appropriate | `arch`, `machine`, `types`, `klib` | boot sequencing policy |
| `services` | kernel-facing interfaces over drivers | console, logging, terminal, later input service | `drivers`, `types`, `klib` | raw bootstrap concerns |
| `core` | orchestration and init flow | `kmain`, panic routing, boot order, runtime checkpoints | `services`, `klib`, `types` | device details and raw machine code |

How the current repo maps to this model:
- `src/arch/i386/boot.asm` and `src/arch/i386/linker.ld` map to `arch`
- `src/kernel/types/port.rs` maps to `machine` or a machine-adjacent typed primitive file
- `src/kernel/types.rs` and `src/kernel/types/range.rs` map to `types`
- `src/kernel/string.rs` and `src/kernel/memory.rs` map to `klib` ABI-surface files
- `src/kernel/string/string_impl.rs` and `src/kernel/memory/memory_impl.rs` map to `klib` internal leaf files
- `src/kernel/vga.rs` currently mixes `drivers` and a minimal surface API; later it should split into a driver leaf plus a thinner screen-facing surface if the subsystem grows
- `src/kernel/kmain.rs` maps to `core`
- `src/kernel/kmain/logic_impl.rs` maps to internal `core` logic, not a public boundary

ABI rule across the layers:
- `arch` is allowed and expected to expose ABI because it crosses ASM/linker boundaries
- `klib` may expose ABI for stable primitive helper families such as `kfs_strlen` and `kfs_memcpy`
- `drivers` may expose ABI only for explicitly designated low-level entry surfaces such as the current `vga_*` family
- `types` should almost never be an ABI-export layer
- `core` may expose ABI only when it is the handoff entry surface, such as `kmain`

### 5.3 Dependency rule summary

Hard rule:
- dependencies may point downward only

Therefore:
- `core` may call `services`, and in the current repo it may still call designated low-level ABI-surface files directly where the higher-level service layer does not exist yet
- `services` may call `drivers`, but should not reimplement hardware access
- `drivers` may use `machine`, `types`, and `klib`
- `klib` must remain device-agnostic and should not accumulate boot orchestration or hardware policy
- `types` must not become a dumping ground for behavior-heavy policy code or exported ABI wrappers

Current incorrect patterns that this rule rejects:
- moving helper logic into `types` because both are "low level"
- exporting leaf files such as `string_impl.rs` or `memory_impl.rs` just because a caller wants direct access
- treating every new top-level kernel file as a separate ABI component
- letting `kmain` own more device-specific behavior once a driver or service file exists

What changes immediately:
- `kmain.rs -> kfs_strlen / kfs_strcmp / kfs_memcpy / kfs_memset / vga_*` is still allowed
- `kmain.rs -> string_impl::*` or `memory_impl::*` is not allowed
- `vga.rs -> Port` or `KernelRange` as internal semantic helpers is allowed
- exporting `Port` or `KernelRange` as ABI symbols is not allowed by default

### 5.4 Ownership model

| Concern | Owner |
|---|---|
| boot entry, stack setup, multiboot handoff | `arch` |
| raw x86 port semantics | `machine` |
| shared semantic wrappers such as `KernelRange` | `types` |
| `memcpy`, `memset`, `strlen`, `strcmp` | `klib` |
| VGA memory and text-mode device details | `drivers` |
| screen/console API used by the rest of the kernel | `services` |
| boot sequencing and feature bring-up | `core` |

Current repo reading of that ownership:
- `kmain` owns boot flow, sanity checks, and the first integration path
- `string.rs` / `memory.rs` own the stable low-level helper entry surface
- `string_impl.rs` / `memory_impl.rs` own only the leaf algorithm details
- `vga.rs` currently owns both low-level VGA behavior and the first screen entry surface; that is acceptable now, but it is the first candidate for a later driver/service split if screen behavior grows
- `types.rs` owns semantic meaning such as `KernelRange`; it does not own helper families or exported ABI wrappers

---

## 6. Architecture decision ledger

### Decision A: kernel family

Decision:
- monolithic kernel

Why:
- one bootable kernel binary is already the required delivery unit
- the subject never requires user-space services or IPC-separated components
- future screen/input work benefits more from internal subsystem layering than from process separation

Source:
- local: `docs/subject.pdf`, `docs/kfs1_epics_features.md`
- external: [OSDev Kernel](https://wiki.osdev.org/Kernel), [OSDev Monolithic Kernel](https://wiki.osdev.org/Monolithic_Kernel)

Immediate consumer:
- current build, linker, and boot path

Future consumer:
- all later subject features

### Decision B: internal boundary model

Decision:
- use a stratified boundary model:
  - true external/toolchain edges use ABI
  - selected low-level kernel surface files may also expose ABI
  - private implementation and richer typed policy code remain Rust-internal by default

Why:
- the subject requires interfaces, but it does not require every internal file to become a separate ABI component
- low-level helper families and simple device entry surfaces benefit from stable symbol contracts
- richer typed/stateful internals become awkward if everything is forced through primitive ABI signatures
- ad hoc mixing is the real bug; rule-based stratification is the fix

Source:
- local: current Makefile and current mixed boundary model
- external: [Phil Opp: VGA Text Mode](https://os.phil-opp.com/vga-text-mode/), [OSDev Kernel](https://wiki.osdev.org/Kernel)

Immediate consumer:
- current Rust kernel source organization

Future consumer:
- future screen, keyboard, terminal, and logging subsystems

### Decision C: shared semantic types

Decision:
- keep shared types only when they encode stable domain meaning

Why:
- `Port` and `KernelRange` already prove the value of meaningful typed concepts
- wrapping every primitive would create artificial architecture
- later screen/input features justify additional semantic types such as cursor position or color code

Source:
- local: `docs/kfs1_repo_status.md` M5.1 notes and existing `types.rs`
- external: [OSDev Port I/O](https://wiki.osdev.org/Port_IO), [OSDev VGA Hardware](https://wiki.osdev.org/VGA_Hardware)

Immediate consumer:
- existing helper and runtime sanity paths

Future consumer:
- screen, serial, cursor, and keyboard features

### Decision D: helper-library ownership

Decision:
- string and memory helper families belong to a dedicated freestanding helper layer, not to `kmain` or device drivers

Why:
- helper families are cross-cutting primitives
- they should not depend on a device or on orchestration policy
- later kernel code will depend on them broadly

Source:
- local: existing `string.rs`, `memory.rs`, M5 backlog and proofs
- external: [OSDev C Library](https://wiki.osdev.org/C_Library), [OSDev Sysroot](https://wiki.osdev.org/Sysroot)

Immediate consumer:
- current helper implementations and runtime proofs

Future consumer:
- all later Rust kernel subsystems

### Decision E: driver versus service split

Decision:
- separate hardware-specific driver code from kernel-facing service APIs

Why:
- the screen interface required by the subject is not the same thing as raw VGA memory writes
- a later terminal/logging/input stack needs a service surface above the hardware implementation
- this separation lets `kmain` target a stable console/service API instead of a specific device forever

Source:
- local: M6, B1, B2, B3, B4, B5 decomposition in `docs/kfs1_epics_features.md`
- external: [Phil Opp: VGA Text Mode](https://os.phil-opp.com/vga-text-mode/), [Linux Driver Model Overview](https://www.kernel.org/doc/html/latest/driver-api/driver-model/overview.html)

Immediate consumer:
- current screen-output feature design

Future consumer:
- scrolling, color, terminal, keyboard echo, and multi-screen work

### Decision F: `kmain` ownership

Decision:
- `kmain` is the boot orchestration layer, not the home of subsystem logic

Why:
- orchestration code and subsystem logic grow at different rates
- if `kmain` owns device details, every later feature pushes unrelated logic into the entrypoint
- keeping `kmain` thin makes later evolution cheaper

Source:
- local: current `kmain` already carries several responsibilities and is the natural place to reduce rather than expand
- external: [OSDev Bare Bones](https://wiki.osdev.org/Bare_Bones), [Phil Opp: VGA Text Mode](https://os.phil-opp.com/vga-text-mode/)

Immediate consumer:
- current boot/runtime flow

Future consumer:
- all later services initialized during bring-up

---

## 7. Recommended module tree

This is the recommended target tree, not a statement that the repo already has it.

Status: define now, integrate later

```text
src/
  arch/
    i386/
      boot.asm
      linker.ld
      ...

  kernel/
    mod.rs

    core/
      mod.rs
      kmain.rs
      panic.rs
      init.rs

    machine/
      mod.rs
      port.rs
      ...

    types/
      mod.rs
      kernel_range.rs
      screen_pos.rs
      color_code.rs
      ...

    klib/
      mod.rs
      string.rs
      memory.rs

    drivers/
      mod.rs
      vga_text.rs
      serial_16550.rs
      keyboard_ps2.rs

    services/
      mod.rs
      console.rs
      log.rs
      terminal.rs
```

### How that maps to the current repo

| Current artifact | Target owner |
|---|---|
| `src/kernel/kmain.rs` | `kernel/core/kmain.rs` |
| `src/kernel/types.rs` and `types/*` | `kernel/types/` or `kernel/machine/` depending on concept |
| `src/kernel/string.rs` | `kernel/klib/string.rs` |
| `src/kernel/memory.rs` | `kernel/klib/memory.rs` |
| `src/kernel/vga.rs` | `kernel/drivers/vga_text.rs` |
| future screen API over VGA | `kernel/services/console.rs` |

---

## 8. Data and ABI conventions

### 8.1 Terms

`ABI boundary`
- a binary-level interface that survives separate compilation or language/toolchain boundaries

`source/module boundary`
- a compile-time boundary inside one Rust kernel source tree; this is still a real contract, expressed through modules, types, visibility, and call rules rather than binary calling conventions

`driver`
- hardware-specific implementation code

`service`
- kernel-facing API built above one or more drivers

`semantic type`
- a type that encodes stable domain meaning, not merely a wrapped primitive

### 8.2 Allowed ABI boundaries

Allowed:
- ASM to Rust entrypoints
- linker-provided symbols
- designated kernel ABI-surface files with stable primitive or low-level entry signatures
- any future boundary explicitly promoted by architecture decision

Forbidden as the default rule:
- creating C ABI surfaces only because two Rust kernel subsystems live in different files
- exporting leaf implementation files or `types` internals as ABI surfaces

Current designated kernel ABI-surface files:
- `src/kernel/kmain.rs`
- `src/kernel/string.rs`
- `src/kernel/memory.rs`
- `src/kernel/vga.rs`

Current internal-only files:
- `src/kernel/kmain/logic_impl.rs`
- `src/kernel/string/string_impl.rs`
- `src/kernel/memory/memory_impl.rs`
- `src/kernel/types.rs`
- `src/kernel/types/port.rs`
- `src/kernel/types/range.rs`

Programmatic enforcement rule:
- only designated ABI-surface files may contain exported `#[no_mangle] pub extern "C"` functions
- internal-only files must not contain exported `#[no_mangle] pub extern "C"` functions
- nested implementation files under `src/kernel/*/` are private by default unless a later architecture decision explicitly promotes one

### 8.3 Allowed data forms

Allowed now:
- primitive integers and pointers for low-level machine and helper code where appropriate
- semantic wrappers for stable concepts such as ports and memory/layout ranges
- later semantic screen/input types when the domain expands

Forbidden:
- wrapping primitives with no stable semantic value
- putting policy-heavy behavior into the shared-type layer
- letting driver-specific raw details become the public interface of `core`

---

## 9. Runtime and integration path

### Current runtime path

Status: exists now
- GRUB loads the kernel
- ASM establishes the early machine state
- control transfers to `kmain`
- `kmain` performs runtime checks and then reaches screen output

### Target runtime path

Status: define now, integrate later
- GRUB loads the kernel
- `arch` hands off into `core`
- `core` initializes services
- `services::console` selects and uses a screen backend
- the concrete backend is implemented by a driver such as VGA text mode

Why this path matters:
- it preserves the same boot flow while improving ownership
- it lets future output changes happen below `core`

---

## 10. Acceptance criteria

- The repository has one documented kernel architecture instead of multiple implicit boundary styles.
- Every new kernel concern can be placed into one of the defined layers without inventing a new pattern.
- ABI boundaries follow the stratified kernel ABI rule rather than ad hoc per-file choice.
- Helper families, shared semantic types, drivers, and orchestration have distinct owners.
- The proposed architecture supports current mandatory features and later screen/input growth without requiring a family-level redesign.

---

## 11. Proof matrix

This document is architecture policy, so its proofs are primarily workflow and design proofs.

### WP-ARCH-1

Assertion:
- the current repo uses multiple boundary styles simultaneously

Evidence:
- `Makefile` compiles top-level `src/kernel/*.rs` files independently
- `types.rs` and `*_impl.rs` are source-included instead

Failure caught:
- pretending the repo already has one clear module model

Status:
- exists now

### WP-ARCH-2

Assertion:
- the subject requires both immediate screen output and later screen/input growth

Evidence:
- `docs/subject.pdf`
- `docs/kfs1_epics_features.md` M6, B1, B2, B3, B4, B5

Failure caught:
- choosing an architecture optimized only for "print 42" and not for later subject scope

Status:
- exists now

### WP-ARCH-3

Assertion:
- the chosen architecture matches recognized monolithic-kernel and subsystem patterns

Evidence:
- OSDev family pages
- Phil Opp VGA writer design
- Linux driver-model overview

Failure caught:
- inventing a repo architecture disconnected from known kernel design patterns

Status:
- exists now

### AT-ARCH-1

Assertion:
- the architecture prevents later features from forcing `kmain` to accumulate device-specific logic

Evidence:
- layer and ownership rules in this document

Failure caught:
- `kmain` becoming the default home of every new feature

Status:
- to add as repo policy enforcement later

### AT-ARCH-2

Assertion:
- the architecture allows new screen behavior such as cursor, scroll, and color without redefining the boundary model

Evidence:
- services over drivers
- semantic types reserved for stable screen concepts

Failure caught:
- later screen features forcing a second architecture rewrite

Status:
- to add as repo policy enforcement later

### RT-ARCH-1

Assertion:
- new internal Rust subsystems must not default to `extern "C"` boundaries without justification

Evidence:
- ABI convention rules in this document

Failure caught:
- continuing the accidental pseudo-component model indefinitely

Status:
- to add as repo policy enforcement later

---

## 12. Common bad implementations

- Treating every new top-level Rust file as a separate ABI component because the current Makefile happens to compile that way
- Letting `kmain` directly own every new subsystem because it is already in the runtime path
- Promoting driver-internal raw details to the public interface of the rest of the kernel
- Creating semantic wrapper types for every primitive regardless of domain value
- Refusing shared semantic types even when a concept is clearly stable and reused
- Collapsing helper-library code, drivers, and orchestration into one layer
- Mistaking "monolithic kernel" for "no internal architecture"

---

## 13. Explicit exclusions

This document does not yet define:
- the exact refactor sequence to move the repo into the target tree
- exact Rust crate layout and build-script changes needed to leave the current Makefile model
- exact names for every future service and driver file
- runtime-loadable module support
- user-space process boundaries
- scheduler, VFS, paging, allocator, or interrupt-subsystem architecture beyond the layer rules

Those remain later design work.

---

## 14. Source basis

### Local sources
- `docs/subject.pdf`
- `docs/kfs1_epics_features.md`
- `docs/kfs1_repo_status.md`
- `Makefile`
- current source tree under `src/kernel/` and `src/arch/i386/`

### External sources
- [OSDev Kernel](https://wiki.osdev.org/Kernel)
- [OSDev Monolithic Kernel](https://wiki.osdev.org/Monolithic_Kernel)
- [OSDev Modular Kernel](https://wiki.osdev.org/Modular_Kernel)
- [OSDev Microkernel](https://wiki.osdev.org/Microkernel)
- [OSDev Hybrid Kernel](https://wiki.osdev.org/Hybrid_Kernel)
- [OSDev Bare Bones](https://wiki.osdev.org/Bare_Bones)
- [OSDev Sysroot](https://wiki.osdev.org/Sysroot)
- [OSDev C Library](https://wiki.osdev.org/C_Library)
- [OSDev Port I/O](https://wiki.osdev.org/Port_IO)
- [OSDev VGA Hardware](https://wiki.osdev.org/VGA_Hardware)
- [Phil Opp: VGA Text Mode](https://os.phil-opp.com/vga-text-mode/)
- [Phil Opp: Unit Testing](https://os.phil-opp.com/unit-testing/)
- [Linux Driver Model Overview](https://www.kernel.org/doc/html/latest/driver-api/driver-model/overview.html)
