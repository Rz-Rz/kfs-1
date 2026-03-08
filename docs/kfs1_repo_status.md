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
  - Proof: `make test arch=i386` (builds a Rust-linked test kernel and enforces the M0.2 checks on it)
- Base Epic M1 DoD: ✅ YES (ISO + disk-image artifacts + automated boot checks)
  - Proof: `file build/os-i386.iso` -> ISO 9660 (bootable)
  - Proof: `file build/os-i386.img` -> ISO 9660 (bootable)
  - Proof: `test $(wc -c < build/os-i386.iso) -le 10485760` (<= 10 MB)
  - Proof: `test $(wc -c < build/os-i386.img) -le 10485760` (<= 10 MB)
  - Proof: `make test arch=i386` (checks the tracked release ISO/IMG size/type and boots both test ISO and test IMG headlessly)
- Base Epic M2 DoD: ✅ YES (header is placed early, ASM sets a stack, and control reaches `kmain`)
  - Proof: `make test arch=i386` (includes the ASM entry, stack, and `call kmain` path in the release kernel build + boot flow)
- Base Epic M3 DoD: ✅ YES (custom linker script, standard sections, exported layout symbols)
  - Proof: `make test arch=i386` (includes M3.2 + M3.3 checks)
- Base Epic M4 DoD: ✅ YES (Rust entry, early-init/runtime assumptions, and halt behavior are all proven)
  - Proof: `make test arch=i386` (includes release-kernel `kmain` export/callsite checks, ordered runtime markers, runtime rejection tests, and halt-path checks)
- Base Epic M5 DoD: ❌ NO
  - Proof: `make test arch=i386` now proves `M5.1` end to end (`Port`, `KernelRange`, type facade, runtime integration, rejection gates), but `M5.2` is still only partial and `M5.3` is still missing
- Base Epic M6 DoD: ❌ NO
  - Proof: `src/kernel/kmain.rs` prints `42`, but there is still no reusable screen interface/module as required by M6.1/M6.2
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
- Base Epic M5 (kernel library helpers): ⚠️
- Base Epic M6 (screen I/O interface + prints 42): ❌
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
- `make test arch=i386` (asserts the test kernel includes ASM+Rust symbols, then runs the four “no host libs (ELF checks)” steps)
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
- `make test arch=i386` (includes ISO build + size/type checks and a headless GRUB boot gate)

### Feature M1.2: "Install GRUB on a virtual image" (alternate path: tiny disk image)
Status: ✅ Done (repo implementation: ISO-content disk image, booted via `-drive`)
Evidence:
- `build/os-i386.img` exists and is <= 10 MB
- Boot test runs via QEMU `-drive ...` and exits PASS/FAIL (no hang)
Proof:
- `make img arch=i386` (produces `build/os-i386.img`)
- `test $(wc -c < build/os-i386.img) -le 10485760 && echo "IMG <= 10MB"`
- `make test arch=i386` (includes build + checks + `scripts/boot-tests/qemu-boot.sh i386 drive`)

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
- ASM transfers control to Rust via `call kmain`; Rust entrypoint is defined in `src/kernel/kmain.rs`
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
- Rust references these layout symbols from `src/rust/layout_symbols.rs`
- Repo proofs validate symbol ordering and reject malformed linker layouts
Proof:
- `rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end|ASSERT)\\b" -S src/arch/i386/linker.ld`
- `nm -n build/kernel-i386.bin | rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b"`
- `rg -n "kernel_start|kernel_end|bss_start|bss_end|addr_of!" -S src/rust/layout_symbols.rs`
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
- `rg -n "write_volatile|b'4'|b'2'" -S src/kernel/kmain.rs`

Epic DoD (M4) complete? ✅

---

## Base Epic M5: Basic Kernel Library (Helpers)

Status: ⚠️ Partial (`M5.1` done; `M5.2` partial; `M5.3` missing)
Evidence:
- `M5.1` is now implemented as a real type/helper scaffold:
  - `src/kernel/types.rs`
  - `src/kernel/types/port.rs`
  - `src/kernel/types/range.rs`
  - `Port(u16)` is used by the live serial / port-I/O path in `src/kernel/kmain.rs`
  - `KernelRange` is used by the live runtime-layout path in `src/kernel/kmain.rs` and `src/kernel/kmain/logic_impl.rs`
  - host, source-architecture, runtime, and rejection proofs exist for `M5.1`
- `M5.2` exists only partially:
  - `strlen` / `strcmp` algorithms exist in `src/kernel/string/string_impl.rs`
  - basic host tests exist in `tests/host_string.rs`
  - basic source/build checks exist in `scripts/tests/unit/string-helpers.sh`
  - the implementation still stops short of the current spec:
    - no exported `kfs_strlen` / `kfs_strcmp`
    - no dedicated runtime marker path for string-helper integration
    - no richer adversarial/rejection coverage
    - current string reads still use `read_volatile`, which does not match the intended ordinary-RAM helper contract
- `M5.3` is still absent:
  - no `src/kernel/memory.rs`
  - no `src/kernel/memory/memory_impl.rs`
  - no host/runtime/rejection tests for `memcpy` / `memset`
Proof:
- `bash scripts/tests/unit/type-architecture.sh i386 port-host-unit-tests-pass`
- `bash scripts/tests/unit/type-architecture.sh i386 kernel-range-host-unit-tests-pass`
- `bash scripts/boot-tests/type-architecture.sh i386 runtime-serial-path-works-with-port`
- `bash scripts/boot-tests/type-architecture.sh i386 runtime-layout-path-works-with-kernel-range`
- `bash scripts/rejection-tests/type-architecture-rejections.sh i386 std-in-helper-layer-fails`
- `bash scripts/rejection-tests/type-architecture-rejections.sh i386 helper-wrapper-missing-extern-c-fails`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strlen-unit-tests-pass`
- `bash scripts/tests/unit/string-helpers.sh i386 host-strcmp-unit-tests-pass`
- `bash scripts/tests/unit/string-helpers.sh i386 release-kernel-links-string-helper-marker`
- `rg -n "\\bfn\\s+(strlen|strcmp)\\b|read_volatile" -S src/kernel/string`
- `make test arch=i386`
What’s left:
- M5.2: finish the current string-helper spec:
  - export `kfs_strlen` / `kfs_strcmp`
  - move from marker-only linkage proof to real runtime integration proof
  - replace `read_volatile` with ordinary RAM reads
  - add richer adversarial and rejection tests
- M5.3: implement `memcpy` / `memset` plus the matching unit / runtime / rejection proofs

---

## Base Epic M6: Screen I/O Interface + Mandatory Output

### Feature M6.3: Mandatory output: display `42`
Status: ✅ Done
Evidence:
- `kmain` writes `4` then `2` directly to the VGA text buffer
Proof:
- `rg -n "0xb8000|write_volatile" -S src/kernel/kmain.rs`
- `rg -n "b'4'|b'2'" -S src/kernel/kmain.rs`

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
- Update `README.md` with the expected output 42 once the screen interface is implemented.

---

## Infra Epics Status (I0–I4)

Status: ⚠️ Partial
Evidence:
- Infra Epic **I0** (Deterministic QEMU PASS/FAIL): ✅ Done
  - Proof: `make test arch=i386` exits deterministically (PASS) and never hangs
  - Proof: `make test arch=i386 KFS_TEST_FORCE_FAIL=1` fails deterministically
- Infra Epic **I3** (Reproducible Dev Environment): ✅ Done
  - Proof: `make container-env-check`
- Infra Epic **I4** (Linker / ELF Hygiene Gates): ⚠️ Partial
  - Proof: `make test arch=i386` includes visible subsection / COMMON / allocatable-section hygiene checks
  - Gap: no linker map file generation/check yet
  - Gap: no `--orphan-handling=error` gate yet
  - Gap: no explicit per-section denylist step yet (current allowlist already caught `.eh_frame`)
- Infra Epic **I1** (Serial console assertions): ❌ Not done
- Infra Epic **I2** (VGA memory assertions): ❌ Not done
