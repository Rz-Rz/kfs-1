# KFS_1 Repo Status vs Subject (Done / Not Done + Priorities)

Snapshot date: March 8, 2026.

This file is an analysis of the current repository state against the backlog in:
- `docs/kfs1_epics_features.md` (baseline spec/backlog)

Scope:
- Focus on **Base (Mandatory)** epics (M0–M8).
- Bonus epics are listed as deferred (not required right now).

As-of snapshot:
- Kernel artifact present: `build/kernel-i386.bin` (ELF32, Intel 80386)
- ISO artifact present: `build/os-i386.iso` (bootable ISO9660, <= 10 MB)
- Disk-image artifact present: `build/os-i386.img` (bootable ISO9660, <= 10 MB; boots via QEMU `-drive`)
- Sources present in ASM under `src/arch/i386/` and Rust under `src/rust/` + `src/kernel/`
- Chosen language: **Rust** (`kmain` exists, is called from ASM, and currently prints `42`)

---

## Epic Validation Summary (DoD YES/NO)

Per-epic DoD verdicts, with proof pointers. Detailed per-feature validations (each with
its own `Proof:`) start in the "Base (Mandatory) Detailed Status" section.

- Base Epic M0 DoD: ✅ YES (i386 target + freestanding/no-host-libs enforced in `make test` on a Rust-linked kernel)
  - Proof: `readelf -h build/kernel-i386.bin` -> `Class: ELF32`, `Machine: Intel 80386`
  - Proof: `make test` (builds a Rust-linked test kernel and enforces the M0.2 checks on it)
- Base Epic M1 DoD: ✅ YES (ISO + disk-image artifacts + automated boot checks)
  - Proof: `file build/os-i386.iso` -> ISO 9660 (bootable)
  - Proof: `file build/os-i386.img` -> ISO 9660 (bootable)
  - Proof: `test $(wc -c < build/os-i386.iso) -le 10485760` (<= 10 MB)
  - Proof: `test $(wc -c < build/os-i386.img) -le 10485760` (<= 10 MB)
  - Proof: `make test` (checks the tracked release ISO/IMG size/type and boots both test ISO and test IMG headlessly)
- Base Epic M2 DoD: ✅ YES (header is placed early, ASM sets a stack, and control reaches `kmain`)
  - Proof: `make test` (includes the ASM entry, stack, and `call kmain` path in the release kernel build + boot flow)
- Base Epic M3 DoD: ✅ YES (custom linker script, standard sections, exported layout symbols)
  - Proof: `make test` (includes M3.2 + M3.3 checks)
- Base Epic M4 DoD: ✅ YES (Rust entry, early-init/runtime assumptions, and halt behavior are all proven)
  - Proof: `make test` (includes release-kernel `kmain` export/callsite checks, ordered runtime markers, runtime rejection tests, and halt-path checks)
- Base Epic M5 DoD: ✅ YES
  - Proof: `make test` now proves `M5.1`, `M5.2`, and `M5.3` end to end (`Port`, `KernelRange`, string-helper ABI, memory-helper ABI, runtime integration, and rejection gates)
- Base Epic M6 DoD: ✅ YES
  - Proof: the mandatory screen path exists, the normal success flow prints `42` through it, and cursor/scroll behavior remains bonus-owned follow-up work rather than a base-epic blocker
- Base Epic M7 DoD: ✅ YES (Makefile builds ASM+Rust, links with custom `.ld`, produces ISO/IMG, runs QEMU)
  - Proof: `make -n all arch=i386 | rg -n "\\brustc\\b"`
  - Proof: `make all arch=i386 && nm -n build/kernel-i386.bin | rg -n "\\bkfs_rust_marker\\b"`
- Base Epic M8 DoD: ⚠️ PARTIAL
  - Proof: ISO exists and is small, and a `README.md` quickstart exists

---

## Environment Readiness (This Machine)

Canonical workflow:
- Run builds and tests inside the container toolchain
- Use `make test` for the daily red or green result

Host requirements:
- `docker` or `podman`

Proof:
- `command -v docker || command -v podman`
- `make container-env-check`

---

## High-Level Base Status (Per Epic DoD)

Legend:
- ✅ DoD met
- ⚠️ Partial (some features done, but DoD not met)
- ❌ Not met

- Base Epic M0 (i386 + freestanding compliance): ✅
- Base Epic M1 (GRUB bootable image <= 10 MB): ✅
- Base Epic M2 (Multiboot header + ASM bootstrap): ✅
- Base Epic M3 (custom linker script + layout): ✅
- Base Epic M4 (kernel in chosen language): ✅
- Base Epic M5 (kernel library helpers): ✅
- Base Epic M6 (screen I/O interface + prints 42): ✅
- Base Epic M7 (Makefile compiles ASM + language, links, image, run): ✅
- Base Epic M8 (turn-in packaging): ⚠️

---

# Base (Mandatory) Detailed Status (Per Feature)

## Base Epic M0: i386 + Freestanding Compliance

### Feature M0.1: Make i386 the explicit default target
Status: ✅ Done
Evidence:
- `Makefile` defaults `arch ?= i386`
- NASM assembles with `nasm -felf32`
- Link uses `ld -m elf_i386`
- Run uses `qemu-system-i386`
- `build/kernel-i386.bin` is `ELF 32-bit ... Intel 80386`
Proof:
- `rg -n "^arch \\?=" Makefile`
- `rg -n "\\bnasm\\b.*-felf32" Makefile`
- `rg -n "\\bld\\b.*-m elf_i386" Makefile`
- `rg -n "qemu-system-i386" Makefile`
- `readelf -h build/kernel-i386.bin | rg -n "Class:|Machine:"`

### Feature M0.2: Enforce "no host libs" and "freestanding" rules
Status: ✅ Done (exercised by Rust + enforced via `make test`)
Evidence:
- Rust code is compiled and linked into the kernel image (symbol `kfs_rust_marker`).
- M0.2 is enforced by inspecting the linked ELF (no dynamic loader/sections, no undefined symbols, no libc/loader markers).
- Dedicated rejection tests now contaminate a real kernel build with hosted-runtime metadata and prove the gate fails.
Proof:
- `make test` (asserts the test kernel includes ASM+Rust symbols, then runs the four “no host libs (ELF checks)” steps)
- `nm -n build/kernel-i386-test.bin | rg -n "\\bkfs_rust_marker\\b"`
- `nm -n build/kernel-i386.bin | rg -n "\\bkfs_rust_marker\\b"` (release kernel also links Rust)
- `KFS_M0_2_INCLUDE_RELEASE=1 bash scripts/boot-tests/freestanding-kernel.sh i386 all` (checks both test + release kernels)
- `bash scripts/rejection-tests/freestanding-rejections.sh i386 interp-pt-interp-present`
- `bash scripts/rejection-tests/freestanding-rejections.sh i386 dynamic-section-present`
- `bash scripts/rejection-tests/freestanding-rejections.sh i386 unresolved-external-symbol`
- `bash scripts/rejection-tests/freestanding-rejections.sh i386 host-runtime-marker-strings`

### Feature M0.3: Size discipline baked into workflow
Status: ✅ Mostly done (image size)
Evidence:
- `build/os-i386.iso` is <= 10 MB
Proof:
- `ISO=build/os-i386.iso; test $(wc -c < "$ISO") -le 10485760 && echo "ISO <= 10MB"`

Epic DoD (M0) complete? ✅

Note:
- M0.1 is complete (i386 toolchain + ELF32).
- M0.2 is enforced on a Rust-linked kernel artifact via `make test` (Rust is present and `kmain` is linked into the release kernel).

---

## Base Epic M1: GRUB Bootable Virtual Image (<= 10 MB)

### Feature M1.1: Provide a minimal GRUB-bootable image (primary path: ISO)
Status: ✅ Done (artifact checks + automated boot gate)
Evidence:
- `build/os-i386.iso` exists and is a bootable ISO9660 image
Proof:
- `file build/os-i386.iso`
- `test $(wc -c < build/os-i386.iso) -le 10485760 && echo "ISO <= 10MB"`
Automated proof:
- `make test` (includes ISO build + size/type checks and a headless GRUB boot gate)

### Feature M1.2: "Install GRUB on a virtual image" (alternate path: tiny disk image)
Status: ✅ Done (repo implementation: ISO-content disk image, booted via `-drive`)
Evidence:
- `build/os-i386.img` exists and is <= 10 MB
- Boot test runs via QEMU `-drive ...` and exits PASS/FAIL (no hang)
Proof:
- `make img arch=i386` (produces `build/os-i386.img`)
- `test $(wc -c < build/os-i386.img) -le 10485760 && echo "IMG <= 10MB"`
- `make test` (includes build + checks + `scripts/boot-tests/qemu-boot.sh i386 drive`)

### Feature M1.3: GRUB config uses a consistent Multiboot version
Status: ✅ Done (Multiboot2 consistently used)
Evidence:
- `src/arch/i386/grub.cfg` uses `multiboot2`
- `src/arch/i386/multiboot_header.asm` contains MB2 magic `0xe85250d6`
Proof:
- `rg -n "^\\s*multiboot2\\b" -S src/arch/i386/grub.cfg`
- `rg -n "0xe85250d6" -S src/arch/i386/multiboot_header.asm`

Epic DoD (M1) complete? ✅

---

## Base Epic M2: Multiboot Header + ASM Boot Strap

### Feature M2.1: Valid Multiboot header placed early in the kernel image
Status: ✅ Done
Evidence:
- Header lives in `.multiboot_header`; linker script places it first in `.boot`
Proof:
- `readelf -SW build/kernel-i386.bin | rg -n "\\.boot|\\.multiboot_header|\\.text"`
- `nm -n build/kernel-i386.bin | rg -n "header_(start|end)|\\bstart\\b"`

### Feature M2.2: ASM entry point sets up a safe execution environment
Status: ✅ Done
Evidence:
- `src/arch/i386/boot.asm` sets a known state with `cli`, `cld`, and `mov esp, stack_top`
Proof:
- `rg -n "mov\\s+esp,|stack_(top|bottom)" -S src/arch/i386/boot.asm`
- `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "stack_(top|bottom)"`

### Feature M2.3: Transfer control to a higher-level `kmain`/`main`
Status: ✅ Done
Evidence:
- ASM transfers control to Rust via `call kmain`; Rust entrypoint is defined in `src/kernel/core/entry.rs`
Proof:
- `rg -n "extern\\s+kmain|call\\s+kmain" -S src/arch/i386/boot.asm`
- `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "\\bkmain\\b"`

Epic DoD (M2) complete? ✅

---

## Base Epic M3: Custom Linker Script + Memory Layout

### Feature M3.1: Custom `linker.ld` (do not use host scripts)
Status: ✅ Done (custom script exists and is used)
Evidence:
- `src/arch/i386/linker.ld` exists
- Makefile links using `-T src/arch/$(arch)/linker.ld`
Proof:
- `rg -n "ENTRY\\(|SECTIONS\\s*\\{|\\s*\\.\\s*=\\s*1M;" -S src/arch/i386/linker.ld`
- `rg -n "\\bld\\b.*\\s-T\\s+src/arch/\\$\\(arch\\)/linker\\.ld" -S Makefile`

### Feature M3.2: Provide standard sections for growth
Status: ✅ Done
Evidence:
- Linker script defines `.text`, `.rodata`, `.data`, `.bss`
- The linked kernel contains those sections and includes canary symbols in `.rodata`, `.data`, and `.bss`
- The M3.2 checker now runs immediately after the kernel link step, so `make all` / `make iso` reject malformed ELF layouts before image creation
- Adversarial subsection canaries prove `.rodata.*`, `.data.*`, `.bss.*`, and `COMMON` still fold into the intended output sections
- Allocatable section allowlist stays clean; unexpected runtime sections like `.eh_frame` are rejected by `make test`
- Real bad-linker rejection tests prove the build gate rejects missing/wrong-type `.text`, `.rodata`, `.data`, and `.bss`
Proof:
- `rg -n "^\\s*\\.(text|rodata|data|bss)\\b" -S src/arch/i386/linker.ld`
- `bash scripts/tests/kernel-sections.sh i386`
- `make -n all arch=i386 | rg -n "m3\\.2-kernel-sections\\.sh"`
- `bash scripts/stability-tests/section-stability.sh i386 rodata-wildcard-capture`
- `bash scripts/stability-tests/section-stability.sh i386 data-wildcard-capture`
- `bash scripts/stability-tests/section-stability.sh i386 bss-wildcard-capture`
- `bash scripts/stability-tests/section-stability.sh i386 common-wildcard-capture`
- `bash scripts/stability-tests/section-stability.sh i386 rodata-subsection-marker`
- `bash scripts/stability-tests/section-stability.sh i386 data-subsection-marker`
- `bash scripts/stability-tests/section-stability.sh i386 bss-subsection-marker`
- `bash scripts/stability-tests/section-stability.sh i386 common-bss-marker`
- `bash scripts/stability-tests/section-stability.sh i386 alloc-section-allowlist`
- `bash scripts/rejection-tests/section-rejections.sh i386 text-missing`
- `bash scripts/rejection-tests/section-rejections.sh i386 text-wrong-type`
- `bash scripts/rejection-tests/section-rejections.sh i386 rodata-missing`
- `bash scripts/rejection-tests/section-rejections.sh i386 rodata-wrong-type`
- `bash scripts/rejection-tests/section-rejections.sh i386 data-missing`
- `bash scripts/rejection-tests/section-rejections.sh i386 data-wrong-type`
- `bash scripts/rejection-tests/section-rejections.sh i386 bss-missing`
- `bash scripts/rejection-tests/section-rejections.sh i386 bss-wrong-type`

### Feature M3.3: Export canonical kernel and BSS boundary symbols
Status: ✅ Done
Evidence:
- Linker script exports `kernel_start`, `kernel_end`, `bss_start`, `bss_end`
- Linker script rejects impossible symbol ordering at link time with `ASSERT`
- Rust references these layout symbols from `src/kernel/core/entry.rs`
- Repo proofs validate symbol ordering and reject malformed linker layouts
Proof:
- `rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end|ASSERT)\\b" -S src/arch/i386/linker.ld`
- `nm -n build/kernel-i386.bin | rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b"`
- `rg -n "kernel_start|kernel_end|bss_start|bss_end|addr_of!" -S src/kernel/core/entry.rs`
- `bash scripts/boot-tests/layout-symbols.sh i386`
- `bash scripts/rejection-tests/layout-symbol-rejections.sh i386 bss-before-kernel`
- `bash scripts/rejection-tests/layout-symbol-rejections.sh i386 bss-end-before-bss-start`
- `bash scripts/rejection-tests/layout-symbol-rejections.sh i386 kernel-end-before-bss-end`

Epic DoD (M3) complete? ✅

---

## Base Epic M4: Minimal Kernel in Your Chosen Language

Status: ✅ Done
Evidence:
- M4.1: release ELF exports `kmain`, the real `start` block calls it, and runtime boot tests now
  prove Rust entry is actually executed
- M4.2: a dedicated Rust early-init checks the BSS zero canary and exported layout bounds before
  continuing, with ordered success markers and dedicated runtime rejection tests
- M4.3: Rust panic/normal flow and ASM boot all converge to explicit halt behavior, while the test
  build uses a controlled QEMU PASS/FAIL exit instead of weakening the release halt loop
Proof:
- `bash scripts/boot-tests/release-kmain-symbol.sh i386 release-kernel-exports-kmain`
- `bash scripts/boot-tests/release-kmain-callsite.sh i386 release-boot-calls-kmain`
- `bash scripts/boot-tests/runtime-markers.sh i386 runtime-markers-are-ordered`
- `bash scripts/rejection-tests/runtime-init-rejections.sh i386 dirty-bss-canary-fails`
- `bash scripts/rejection-tests/runtime-init-rejections.sh i386 bad-layout-fails`
- `bash scripts/boot-tests/halt-behavior.sh i386 release-kmain-disassembly-halts`
- `rg -n "write_volatile|b'4'|b'2'|run_early_init|console::write_bytes" -S src/kernel/core`

Epic DoD (M4) complete? ✅

---

## Base Epic M5: Basic Kernel Library (Helpers)

Status: ✅ Done (`M5.1`, `M5.2`, and `M5.3` done)
Evidence:
- `M5.1` is now implemented as a real type/helper scaffold:
  - `src/kernel/types/mod.rs`
  - `src/kernel/types/range.rs`
  - `src/kernel/types/screen.rs`
  - `src/kernel/machine/port.rs`
  - `Port(u16)` is used by the live serial / port-I/O path in the architecture-owned runtime path
  - `KernelRange` is used by the live runtime-layout path in `src/kernel/core/entry.rs` and `src/kernel/types/range.rs`
  - host, source-architecture, runtime, and rejection proofs exist for `M5.1`
  - keep as the permanent `M5.1` base:
    - one discoverable type facade
    - `Port(u16)` as the semantic wrapper for x86 port I/O
    - `KernelRange { start, end }` as the semantic wrapper for layout spans
    - live kernel consumers in the serial and layout paths
    - dedicated host / source / runtime / rejection proof assets
- `M5.2` is now implemented as the real string-helper family:
  - `src/kernel/klib/string/imp.rs` owns the scalar leaf algorithms
  - `src/kernel/klib/string/mod.rs` exports `kfs_strlen` and `kfs_strcmp`
  - `src/kernel/core/init.rs` owns the first real string-helper runtime sanity path, entered from `kmain`
  - `tests/host_string.rs` now covers embedded-NUL, unaligned-start, same-pointer, empty/non-empty,
    prefix, and high-byte ordering behavior
  - `scripts/tests/unit/string-helpers.sh` now enforces source, ABI, artifact, and non-volatile-read checks
  - `scripts/boot-tests/string-runtime.sh` now proves the running kernel reaches the string helpers
  - `scripts/rejection-tests/string-rejections.sh` now proves broken string-helper self-checks emit
    `STRING_HELPERS_FAIL` and stop later normal flow
  - keep as the permanent `M5.2` base:
    - the public-family / private-leaf split:
      - `src/kernel/klib/string/mod.rs`
      - `src/kernel/klib/string/imp.rs`
    - the raw scalar leaf algorithms as the correctness baseline
    - the real low-level helper ABI:
      - `kfs_strlen`
      - `kfs_strcmp`
    - the `core/init.rs` runtime sanity path until `M6` becomes the natural consumer
    - the full `UT/WP/SM/AT/RT` proof surface
- `M5.3` is now implemented to the same proof standard as `M5.2`:
  - `src/kernel/klib/memory/mod.rs` exports `kfs_memcpy` and `kfs_memset`
  - `src/kernel/klib/memory/imp.rs` owns the scalar `memcpy` / `memset` leaf algorithms
  - `src/kernel/core/init.rs` owns the first real memory-helper runtime sanity path, entered from `kmain`
  - `tests/host_memory.rs` covers ordinary copy/fill behavior, zero-byte fill, zero-length behavior, return-pointer behavior, same-pointer copy, unaligned copy, and sentinel-preserving bounds
  - `scripts/tests/unit/memory-helpers.sh` enforces source, ABI, release-symbol, and non-volatile ordinary-memory checks
  - `scripts/boot-tests/memory-runtime.sh` proves the running kernel reaches the memory helpers
  - `scripts/rejection-tests/memory-rejections.sh` proves broken memory-helper self-checks emit `MEMORY_HELPERS_FAIL` and stop later normal flow
  - keep from this rebased branch:
    - the public-family / private-leaf split for the memory helper family
    - the real low-level helper ABI:
      - `kfs_memcpy`
      - `kfs_memset`
    - the scalar host-tested baseline for `memcpy` / `memset`
    - the `core/init.rs` runtime sanity path until `M6` becomes the natural consumer
    - the full `UT/WP/SM/AT/RT` proof surface
Proof:
- `bash scripts/tests/unit/type-architecture.sh i386 port-host-unit-tests-pass`
- `bash scripts/tests/unit/type-architecture.sh i386 kernel-range-host-unit-tests-pass`
- `bash scripts/boot-tests/type-architecture.sh i386 runtime-serial-path-works-with-port`
- `bash scripts/boot-tests/type-architecture.sh i386 runtime-layout-path-works-with-kernel-range`
- `bash scripts/rejection-tests/type-architecture-rejections.sh i386 std-in-helper-layer-fails`
- `bash scripts/rejection-tests/type-architecture-rejections.sh i386 helper-wrapper-missing-extern-c-fails`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strlen-unit-tests-pass`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strlen-embedded-nul-stops-first`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strlen-unaligned-start`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strlen-word-boundary`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strcmp-unit-tests-pass`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strcmp-prefix-and-empty-cases`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strcmp-same-pointer`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strcmp-high-byte-ordering`
- `bash scripts/tests/unit/string-helpers.sh i386 rust-exports-kfs-strlen`
- `bash scripts/tests/unit/string-helpers.sh i386 rust-exports-kfs-strcmp`
- `bash scripts/tests/unit/string-helpers.sh i386 release-kernel-exports-kfs-strlen`
- `bash scripts/tests/unit/string-helpers.sh i386 release-kernel-exports-kfs-strcmp`
- `bash scripts/tests/unit/string-helpers.sh i386 string-helpers-avoid-volatile-reads`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memcpy-unit-tests-pass`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memcpy-zero-length-behavior`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memcpy-return-pointer-behavior`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memcpy-same-pointer`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memcpy-unaligned-pointers`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memcpy-sentinel-bounds`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memset-unit-tests-pass`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memset-zero-byte-fill`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memset-zero-length-behavior`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memset-return-pointer-behavior`
- `bash scripts/tests/unit/memory-helpers.sh i386 host-memset-sentinel-bounds`
- `bash scripts/tests/unit/memory-helpers.sh i386 rust-exports-kfs-memcpy`
- `bash scripts/tests/unit/memory-helpers.sh i386 rust-exports-kfs-memset`
- `bash scripts/tests/unit/memory-helpers.sh i386 release-kernel-exports-kfs-memcpy`
- `bash scripts/tests/unit/memory-helpers.sh i386 release-kernel-exports-kfs-memset`
- `bash scripts/tests/unit/memory-helpers.sh i386 memory-helpers-avoid-volatile-access`
- `bash scripts/boot-tests/memory-runtime.sh i386 runtime-confirms-memory-helpers`
- `bash scripts/boot-tests/memory-runtime.sh i386 runtime-memory-markers-are-ordered`
- `bash scripts/rejection-tests/memory-rejections.sh i386 bad-memory-self-check-fails`
- `bash scripts/rejection-tests/memory-rejections.sh i386 bad-memory-stops-before-normal-flow`
- `bash scripts/boot-tests/string-runtime.sh i386 runtime-confirms-string-helpers`
- `bash scripts/boot-tests/string-runtime.sh i386 runtime-string-markers-are-ordered`
- `bash scripts/rejection-tests/string-rejections.sh i386 bad-string-self-check-fails`
- `bash scripts/rejection-tests/string-rejections.sh i386 bad-string-stops-before-normal-flow`
- `rg -n "kfs_strlen|kfs_strcmp|strlen|strcmp" -S src/kernel/klib/string src/kernel/core/init.rs`
- `rg -n "kfs_memcpy|kfs_memset|memcpy|memset" -S src/kernel/klib/memory src/kernel/core/init.rs`
- `make test`
What’s left:
- No open `M5` gaps remain on this branch; the next unfinished base work is still `M6`

---

## Base Epic M6: Screen I/O Interface + Mandatory Output

Status: ✅ Done for mandatory scope

Evidence:
- `src/kernel/types/screen.rs` already owns the current screen-domain types
- `src/kernel/services/console.rs` routes normal screen output through `src/kernel/drivers/vga_text`
- `src/kernel/drivers/vga_text/writer.rs` writes packed text cells to VGA text memory at `0xB8000`
- `src/kernel/core/init.rs` prints `42` through the service-owned screen path
- Headless automation now reads VGA text memory twice, proves the first screen bytes encode `42`, and checks the visible buffer stays stable across monitor snapshots
- Host unit coverage now includes a buffer-backed VGA writer model for write progression and wrap behavior
- The subject's cursor/scroll work is bonus-owned follow-up scope, not a blocker for base `M6`

Gaps / follow-up:
- Cursor/newline/scroll behavior remains bonus-owned follow-up work under `B1`
- The repo still does not expose a richer general-purpose console API beyond the current minimal writer path

Proof:
- `bash scripts/tests/unit/kmain-logic.sh i386 host-vga-cell-unit-tests-pass`
- `bash scripts/tests/unit/vga-writer-model.sh i386 host-vga-writer-sequential-writes`
- `bash scripts/tests/unit/vga-writer-model.sh i386 host-vga-writer-wraps-at-buffer-end`
- `bash scripts/tests/unit/vga-writer-model.sh i386 services-console-keeps-writer-state`
- `bash scripts/boot-tests/vga-writer.sh i386 driver-vga-writer-exists`
- `bash scripts/boot-tests/vga-writer.sh i386 services-console-uses-driver`
- `bash scripts/boot-tests/vga-writer.sh i386 core-init-uses-services-console`
- `bash scripts/architecture-tests/runtime-ownership.sh i386 core-init-calls-services-console`
- `bash scripts/architecture-tests/runtime-ownership.sh i386 services-console-calls-driver-facade`
- `bash scripts/boot-tests/runtime-markers.sh i386 runtime-completes-early-init`
- `bash scripts/boot-tests/vga-memory.sh i386 vga-buffer-starts-with-42`
- `bash scripts/boot-tests/vga-memory.sh i386 vga-buffer-uses-default-attribute`
- `bash scripts/boot-tests/vga-memory.sh i386 vga-buffer-stable-across-snapshots`
- `bash scripts/boot-tests/vga-writer.sh i386 release-kernel-omits-vga-abi-exports`

---

## Base Epic M7: Makefile must compile all sources (ASM + chosen language), link, image, run

Status: ✅ Done
Evidence:
- Makefile assembles ASM, links i386, builds ISO, and runs QEMU.
Proof:
- `make -n iso`
- `make -n all arch=i386 | rg -n "\\brustc\\b"`

---

## Base Epic M8: Turn-in Packaging

Status: ⚠️ Partial
Evidence:
- ISO exists and is <= 10 MB: `build/os-i386.iso`
What’s left:
- Turn-in packaging is still partial for reasons outside the now-corrected VGA screen path.

---

## Infra Epics Status (I0–I4)

Status: ⚠️ Partial
Evidence:
- Infra Epic **I0** (Deterministic QEMU PASS/FAIL): ✅ Done
  - Proof: `make test` exits deterministically (PASS) and never hangs
  - Proof: `make test KFS_TEST_FORCE_FAIL=1` fails deterministically
- Infra Epic **I3** (Reproducible Dev Environment): ✅ Done
  - Proof: `make container-env-check`
- Infra Epic **I4** (Linker / ELF Hygiene Gates): ⚠️ Partial
  - Proof: `make test` includes visible subsection / COMMON / allocatable-section hygiene checks
  - Gap: no linker map file generation/check yet
  - Gap: no `--orphan-handling=error` gate yet
  - Gap: no explicit per-section denylist step yet (current allowlist already caught `.eh_frame`)
- Infra Epic **I1** (Serial console assertions): ❌ Not done
- Infra Epic **I2** (VGA memory assertions): ✅ Done
  - Proof: `make test` includes headless VGA-memory checks for the first `42` screen cells plus repeated monitor snapshots for buffer stability
  - Proof: `make test-vga arch=i386`

---

## Deferred Bonus / Extension Status (B1–B6)

These items are not required for the base KFS_1 subject, but this branch now carries them on top of `main`'s architecture.

High-level status:
- Bonus Epic B1 (scroll + cursor support): ✅ Done
- Bonus Epic B2 (color support in the screen I/O interface): ✅ Done
- Bonus Epic B3 (`printk` / formatted printing): ✅ Done
- Bonus Epic B4 (keyboard input + echo): ✅ Done
- Bonus Epic B5 (multiple screens + keyboard shortcuts): ✅ Done
- Bonus Epic B6 (screen geometry / different screen sizes): ✅ Done

### Bonus Epic B1: Scroll + Cursor Support

Status: ✅ Done
Evidence:
- Cursor state, scroll behavior, and hardware cursor programming now live in `src/kernel/drivers/vga_text/writer.rs`.
- Host coverage for cursor and scroll behavior lives in `tests/host_cursor.rs` and `tests/host_scroll.rs`.
Proof:
- `bash scripts/check-b1.3-hw-cursor.sh i386`
- `bash scripts/tests/unit/vga-history.sh i386`

### Bonus Epic B2: Color Support in the Screen I/O Interface

Status: ✅ Done
Evidence:
- Screen color types live in `src/kernel/types/screen.rs`.
- VGA color state is applied by `src/kernel/drivers/vga_text/mod.rs` and `src/kernel/drivers/vga_text/writer.rs`.
Proof:
- `bash scripts/tests/unit/vga-color.sh i386`

### Bonus Epic B3: `printk` / Formatted Printing

Status: ✅ Done
Evidence:
- Allocation-free formatting and screen printing now flow through `src/kernel/services/console.rs`.
- Host formatting coverage lives in `tests/host_vga_format.rs`.
Proof:
- `bash scripts/tests/unit/console-format.sh i386`

### Bonus Epic B4: Keyboard Input + Echo

Status: ✅ Done
Evidence:
- Keyboard decode and shortcut routing now live under `src/kernel/drivers/keyboard/`.
- The service layer echoes printable input and editing actions through `src/kernel/services/console.rs`.
Proof:
- `bash scripts/tests/unit/keyboard-input.sh i386`

### Bonus Epic B5: Multiple Screens + Keyboard Shortcuts

Status: ✅ Done
Evidence:
- Per-terminal history, redraw, and active-terminal state now live in `src/kernel/drivers/vga_text/mod.rs`.
- Keyboard shortcut routing for terminal selection and lifecycle now lives in `src/kernel/drivers/keyboard/mod.rs` and `src/kernel/drivers/keyboard/imp.rs`.
Proof:
- `bash scripts/tests/unit/vga-vt.sh i386`
- `bash scripts/tests/unit/keyboard-input.sh i386`

### Bonus Epic B6: Screen Geometry / Different Screen Sizes

Status: ✅ Done
Evidence:
- Geometry types and preset selection now live in `src/kernel/types/screen.rs`.
- The VGA text driver renders the logical viewport into the fixed `80x25` hardware buffer through `src/kernel/drivers/vga_text/mod.rs` and `src/kernel/drivers/vga_text/writer.rs`.
- Build-time preset selection is exposed through `KFS_SCREEN_GEOMETRY_PRESET` in `Makefile`.
Proof:
- `bash scripts/tests/unit/vga-geometry.sh i386`
- `bash scripts/tests/unit/vga-geometry-writer.sh i386`
- `bash scripts/tests/unit/vga-geometry-preset.sh i386`
- `KFS_SCREEN_GEOMETRY_PRESET=compact40x10 make -B all arch=i386`
