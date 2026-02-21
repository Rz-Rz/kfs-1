# KFS_1 Repo Status vs Subject (Done / Not Done + Priorities)

This file is an analysis of the current repository state against the backlog in:
- `docs/kfs1_epics_features.md` (do not edit; treated as the baseline spec/backlog)

Scope:
- Focus on **Base (Mandatory)** epics (M0-M8).
- Bonus epics are listed as deferred (not required right now).

As-of snapshot:
- Kernel artifact present: `build/kernel-x86_64.bin` (ELF64, x86-64)
- ISO artifact present: `build/os-x86_64.iso` (~4.9 MB)
- Sources present only in ASM under `src/arch/x86_64/`
- No C/Rust/Go/etc kernel code present

---

## Epic Validation Summary (DoD YES/NO)

Per-epic DoD verdicts, with proof pointers. Detailed per-feature validations (each with
its own `Proof:`) start in the "Base (Mandatory) Detailed Status" section.

- Base Epic M0 DoD: NO
  - Proof: `readelf -h build/kernel-x86_64.bin` -> `Class: ELF64`, `Machine: X86-64` (not i386)
  - Proof: `file build/arch/x86_64/boot.o` -> `ELF 64-bit ... x86-64`
- Base Epic M1 DoD: NO (boot/rebuild not provable on this machine)
  - Proof: `ls -lh build` -> ISO is `4.9M` (<= 10 MB)
  - Proof: `file build/os-x86_64.iso` -> bootable ISO format
  - Proof: `command -v grub-mkrescue qemu-system-i386` -> missing here
- Base Epic M2 DoD: NO
  - Proof: `src/arch/x86_64/boot.asm` has no stack init and no `kmain` call; ends with `hlt`
- Base Epic M3 DoD: NO
  - Proof: `src/arch/x86_64/linker.ld` defines only `.boot` and `.text`, and exports no layout symbols
- Base Epic M4 DoD: NO
  - Proof: `rg -n "\\b(kmain|main)\\b" src` -> no matches (no chosen-language kernel entry)
- Base Epic M5 DoD: NO
  - Proof: `rg -n "\\b(strlen|strcmp|memcpy|memset)\\b" src` -> no matches (no kernel library helpers)
- Base Epic M6 DoD: NO
  - Proof: `src/arch/x86_64/boot.asm` writes "OK"; `rg -n "\\b42\\b|\\\"42\\\"" src` -> no matches
- Base Epic M7 DoD: NO
  - Proof: `Makefile:36` uses `nasm -felf64`; no chosen-language compile rules; `Makefile:19` runs `qemu-system-x86_64`
- Base Epic M8 DoD: NO (partial deliverables only)
  - Proof: ISO exists and is small, but build/run reproducibility is blocked here and `git ls-files` shows no `README*`

## Environment Readiness (This Machine)

These tools are *not available in PATH right now* (so you cannot rebuild/run here):
- `nasm` (missing) -> `Makefile` currently requires it
- `qemu-system-*` (missing) -> cannot run `make run` here
- `grub-mkrescue` / `grub-file` (missing) -> cannot regenerate/validate ISO here

Tools present:
- `ld`, `as`

Impact:
- The repo contains prebuilt artifacts (`build/*`) that may have been built elsewhere,
  but reproducibility and verification are currently blocked on tool installation or
  switching away from NASM/QEMU/GRUB tooling.

---

## High-Level Base Status (Per Epic DoD)

Legend:
- ✅ DoD met
- ⚠️ Partial (some features done, but DoD not met)
- ❌ Not met

- Base Epic M0 (i386 + freestanding compliance): ❌
  - Evidence: `build/kernel-x86_64.bin` is ELF64 x86-64; subject mandates i386.
- Base Epic M1 (GRUB bootable image <= 10 MB): ⚠️
  - Evidence: `build/os-x86_64.iso` exists and is < 10 MB; cannot verify boot here.
- Base Epic M2 (Multiboot header + ASM bootstrap): ❌
  - Evidence: MB2 header exists, but no stack init and no `kmain` handoff.
- Base Epic M3 (custom linker script + layout): ⚠️
  - Evidence: `src/arch/x86_64/linker.ld` exists and places `.multiboot_header` first,
    but layout is minimal and currently targets ELF64 output.
- Base Epic M4 (kernel in chosen language): ❌
  - Evidence: no non-ASM kernel sources exist.
- Base Epic M5 (kernel library types + helpers): ❌
  - Evidence: no types/`strlen`/`strcmp` implementations exist.
- Base Epic M6 (screen I/O interface + prints 42): ❌
  - Evidence: ASM writes `OK` directly to VGA; no screen interface module; no `42`.
- Base Epic M7 (Makefile compiles ASM + language, links, image, run): ❌
  - Evidence: Makefile builds only ASM, uses `nasm -felf64`, links ELF64, runs x86_64 QEMU.
- Base Epic M8 (turn-in packaging): ⚠️
  - Evidence: code + Makefile exist; an image exists and is < 10 MB; no README/how-to.

---

# Base (Mandatory) Detailed Status (Per Feature)

## Base Epic M0: i386 + Freestanding Compliance

### Feature M0.1: Make i386 the explicit default target
Status: ❌ Not done
Evidence:
- `Makefile` defaults `arch ?= x86_64`
- `Makefile` assembles with `nasm -felf64`
- `build/kernel-x86_64.bin` is `ELF 64-bit ... x86-64`
Proof:
- `Makefile:1` (`arch ?= x86_64`) and `Makefile:36` (`nasm -felf64 ...`)
- `file build/arch/x86_64/boot.o` shows ELF64 relocatable x86-64 (assembled output)
- `readelf -h build/kernel-x86_64.bin` shows `Class: ELF64`, `Machine: X86-64`
What’s left:
- Switch to an explicit i386 target (`arch ?= i386` or similar)
- Produce `ELF32` objects (`elf32`) and link with `ld -m elf_i386`

### Feature M0.2: Enforce "no host libs" and "freestanding" rules
Status: ⚠️ Partial / not yet applicable
Evidence:
- Current kernel is ASM-only and linked with `ld` (no libc link step).
Proof:
- `rg --files src` shows only ASM + linker script + grub.cfg under `src/`
- Kernel is `statically linked` per `file build/kernel-x86_64.bin`
What’s left:
- Once a C/Rust/etc kernel is added, enforce freestanding flags and ensure no dynamic sections.

### Feature M0.3: Size discipline baked into workflow
Status: ✅ Mostly done (image size)
Evidence:
- `build/os-x86_64.iso` is ~4.9 MB (< 10 MB)
Proof:
- `ls -lh build` shows `os-x86_64.iso` is `4.9M`
What’s left:
- Ensure the *turned-in* image remains <= 10 MB after future changes.

Epic DoD (M0) complete? ❌
- Blockers: i386 requirement not met; build cannot be reproduced here due to missing `nasm`.

---

## Base Epic M1: GRUB Bootable Virtual Image (<= 10 MB)

### Feature M1.1: Minimal GRUB-bootable image (ISO)
Status: ⚠️ Partial (artifact exists, rebuild/verify blocked)
Evidence:
- `build/os-x86_64.iso` exists and is bootable ISO format
Proof:
- `file build/os-x86_64.iso` reports ISO 9660 bootable
- Local verification blocked: `grub-mkrescue` and `qemu-system-*` are missing in PATH
What’s left:
- Ability to rebuild ISO locally (`grub-mkrescue`) and verify boot (`qemu-system-i386`)

### Feature M1.2: Optional disk image install path
Status: ❌ Not done
Proof:
- `Makefile` only has an ISO recipe using `grub-mkrescue` (no raw disk image build/install steps)
- `git ls-files` shows no disk image artifact tracked besides `build/os-x86_64.iso`
What’s left:
- Create and install GRUB to a tiny disk image (optional, but matches wording)

### Feature M1.3: Consistent Multiboot version and GRUB config
Status: ✅ Done (config + header exist)
Evidence:
- `src/arch/x86_64/grub.cfg` uses `multiboot2`
- `src/arch/x86_64/multiboot_header.asm` is MB2 magic (`0xe85250d6`)
Proof:
- `src/arch/x86_64/grub.cfg:5` is `multiboot2 /boot/kernel.bin`
- `src/arch/x86_64/multiboot_header.asm:3-4` sets MB2 magic and i386 architecture field
What’s left:
- Optional verification using `grub-file` (not installed here).

Epic DoD (M1) complete? ⚠️
- The image exists and is small, but local rebuild/boot verification is currently blocked.

---

## Base Epic M2: Multiboot Header + ASM Boot Strap

### Feature M2.1: Valid Multiboot header placed early
Status: ⚠️ Partial (present + linked early; spec-level validity not verified here)
Evidence:
- Header in `.multiboot_header` section
- Linker script places `*(.multiboot_header)` before `.text`
Proof:
- `src/arch/x86_64/multiboot_header.asm:1-15` defines `.multiboot_header`
- `src/arch/x86_64/linker.ld:6-10` places `*(.multiboot_header)` first
- `readelf -S build/kernel-x86_64.bin` shows `.boot` at `0x100000` (size `0x18`) and `.text` at `0x100020`
- `nm -n build/kernel-x86_64.bin` shows `header_start` at `0x100000` and `start` at `0x100020`
What’s left:
- Verify header constraints and that GRUB accepts it on i386 with the final ELF32 kernel.

### Feature M2.2: ASM entry sets safe execution environment (stack, known state)
Status: ❌ Not done
Evidence:
- `src/arch/x86_64/boot.asm` does not set up a stack
Proof:
- `src/arch/x86_64/boot.asm` contains only a single store and `hlt` (no `mov esp, ...`)
What’s left:
- Reserve a stack region and set `esp` before calling any higher-level code.

### Feature M2.3: Transfer control to `kmain`/`main`
Status: ❌ Not done
Evidence:
- `src/arch/x86_64/boot.asm` prints to VGA and halts (`hlt`)
Proof:
- `rg -n "\\b(kmain|main)\\b" src` returns no matches
What’s left:
- Define an `extern kmain` and `call kmain` (or language equivalent).

Epic DoD (M2) complete? ❌

---

## Base Epic M3: Custom Linker Script + Memory Layout

### Feature M3.1: Custom `linker.ld` used for linking
Status: ✅ Done (minimal)
Evidence:
- `src/arch/x86_64/linker.ld` exists and is used by Makefile
Proof:
- `Makefile:31` links with `-T src/arch/$(arch)/linker.ld`
- Kernel section addresses match `src/arch/x86_64/linker.ld:4` (`. = 1M;`) via `readelf -S build/kernel-x86_64.bin`
What’s left:
- Adjust it for ELF32/i386 once toolchain is corrected.

### Feature M3.2: Standard sections (.text/.rodata/.data/.bss)
Status: ❌ Not done
Evidence:
- Linker script only defines `.boot` and `.text`
Proof:
- `src/arch/x86_64/linker.ld` contains only `.boot` and `.text` output sections
What’s left:
- Add `.rodata`, `.data`, `.bss` and ensure alignment rules are sane.

### Feature M3.3: Export layout symbols
Status: ❌ Not done
Proof:
- `nm -n build/kernel-x86_64.bin` only shows `header_start`, `header_end`, `start` (no `kernel_start/kernel_end/bss_*`)
What’s left:
- Add symbols for `kernel_start/end` and `bss_start/end` (names flexible).

Epic DoD (M3) complete? ⚠️

---

## Base Epic M4: Minimal Kernel in a Chosen Language

### Feature M4.1: `kmain` in chosen language
Status: ❌ Not done
Evidence:
- No kernel sources outside ASM exist.
Proof:
- `rg --files src` lists only ASM + `.ld` + `grub.cfg`
What’s left:
- Pick language (most common: C) and implement `kmain`.

### Feature M4.2: Minimal init pattern
Status: ❌ Not done
Proof:
- No chosen-language `kmain` exists (`rg -n "\\b(kmain|main)\\b" src` returns none), so there is no init sequence beyond ASM

### Feature M4.3: Clean halt behavior
Status: ⚠️ Partial
Evidence:
- Current ASM ends with `hlt` (halts) but without a robust halt loop.
Proof:
- Disassembly of `build/kernel-x86_64.bin` at `<start>` ends with a single `hlt` (no `jmp` loop)
What’s left:
- Provide a defined halt path (e.g., loop) after `kmain` returns.

Epic DoD (M4) complete? ❌

---

## Base Epic M5: Basic Kernel Library (Types + Helpers)

### Feature M5.1: Kernel-owned types
Status: ❌ Not done
Proof:
- `git ls-files` contains no `*.c`, `*.h`, `*.rs`, etc.; `src/` is ASM-only (`rg --files src`)

### Feature M5.2: `strlen` / `strcmp`
Status: ❌ Not done
Proof:
- `rg -n "\\b(strlen|strcmp)\\b" src` returns no matches

### Feature M5.3: `memcpy` / `memset`
Status: ❌ Not done
Proof:
- `rg -n "\\b(memcpy|memset)\\b" src` returns no matches

Epic DoD (M5) complete? ❌

---

## Base Epic M6: Screen I/O Interface + Prints 42

### Feature M6.1: Screen interface module (VGA text writer)
Status: ⚠️ Partial
Evidence:
- Direct VGA write exists in ASM (`mov dword [0xb8000], ...`).
Proof:
- Source intent: `src/arch/x86_64/boot.asm:7` uses `[0xb8000]`
- Built artifact reality: `objdump -d build/kernel-x86_64.bin` shows RIP-relative store `[rip+0xb8000]` (not absolute VGA `0xB8000`)
What’s left:
- A real interface in the chosen language (`putc`, `puts`) callable from `kmain`.

### Feature M6.2: Newline handling / cursor movement
Status: ❌ Not done
Proof:
- Only output logic in repo is a single fixed store in `src/arch/x86_64/boot.asm`; no cursor/newline code exists

### Feature M6.3: Mandatory output "42"
Status: ❌ Not done
Evidence:
- Current output is `OK`, not `42`.
Proof:
- `src/arch/x86_64/boot.asm:6-7` comments/constant correspond to "OK"
- `rg -n "\\b42\\b|\\\"42\\\"" src` returns no matches
What’s left:
- Print `42` (preferably from `kmain` via the screen interface).

Epic DoD (M6) complete? ❌

---

## Base Epic M7: Makefile (ASM + Language + Link + Image + Run)

### Feature M7.1: ASM compiled for i386 correctly
Status: ❌ Not done
Evidence:
- `Makefile` uses `nasm -felf64` (and `nasm` isn’t installed here).
Proof:
- `Makefile:36` uses `-felf64`
- `file build/arch/x86_64/boot.o` is ELF64 relocatable x86-64
- `command -v nasm` fails on this machine (cannot rebuild here)
What’s left:
- Assemble as `elf32` (or switch to GAS with equivalent sources).

### Feature M7.2: Compile chosen-language sources with freestanding flags
Status: ❌ Not done
Proof:
- No non-ASM sources exist (`git ls-files` shows only `.asm` under `src/`)
- `Makefile` has no compilation rules for C/Rust/etc (only NASM rule exists)

### Feature M7.3: Link all objects with custom linker script in i386 mode
Status: ⚠️ Partial
Evidence:
- Links with `ld -T linker.ld`, but produces ELF64 due to inputs and missing `-m elf_i386`.
Proof:
- `Makefile:31` links with `ld -T ...` but does not pass `-m elf_i386`
- Output kernel is ELF64 x86-64 per `readelf -h build/kernel-x86_64.bin`
What’s left:
- Link with `-m elf_i386` once objects are ELF32.

### Feature M7.4: Standard targets exist
Status: ✅ Done
Evidence:
- `all`, `clean`, `run`, `iso` targets exist.
Proof:
- `Makefile:11` declares `.PHONY: all clean run iso` and defines each target below
What’s left:
- Make `run` target use i386 QEMU (and ensure QEMU exists).

Epic DoD (M7) complete? ❌

---

## Base Epic M8: Turn-In Packaging (Defense-Ready)

### Feature M8.1: Required deliverables present
Status: ⚠️ Partial
Evidence:
- Code and Makefile present.
- A bootable image artifact exists in `build/`.
Proof:
- `git ls-files` includes `Makefile` and `src/arch/x86_64/*`
- `git ls-files` includes `build/os-x86_64.iso` and `build/kernel-x86_64.bin` (tracked artifacts)
What’s left:
- Ensure final image matches i386 base requirements and is reproducible.

### Feature M8.2: Enforce <= 10 MB image
Status: ✅ Done (currently)
Evidence:
- `build/os-x86_64.iso` < 10 MB.
Proof:
- `ls -lh build` shows ISO size `4.9M`

### Feature M8.3: Minimal "how to run" notes
Status: ❌ Not done
Proof:
- `git ls-files` contains no `README*`

Epic DoD (M8) complete? ⚠️

---

# Bonus (Deferred) Status

All bonus epics (B1-B5) are currently: ❌ Not started
- This is fine; bonus is only assessed after mandatory is perfect.

---

## Priority: What To Focus On First (Starting Point)

If the goal is a fast, defensible KFS_1 mandatory pass, focus on the smallest path to:
**i386 GRUB boot -> enters `kmain` -> prints `42` via a screen interface -> halts**.

### Priority 1 (Focus Now): Fix i386 toolchain + build correctness
Why:
- The subject explicitly mandates i386; current artifact is x86-64 (likely a hard fail).
- Everything else builds on having a correct, reproducible kernel binary.

Deliverable for this priority:
- `make` produces an `ELF32` i386 kernel using your own linker script.

### Priority 2: Add chosen-language kernel entry and call it from ASM
Why:
- Subject expects ASM + chosen language, and GRUB should "call main function".

Deliverable:
- `kmain()` exists (e.g., C) and is invoked from ASM after stack init.

### Priority 3: Implement screen interface and print `42` from `kmain`
Why:
- Mandatory functional requirement is printing `42` and having a screen I/O interface.

Deliverable:
- `puts("42")` (or equivalent) prints on VGA text mode.

### Priority 4: Add minimal kernel library helpers (types, strlen/strcmp)
Why:
- Explicitly mentioned in the mandatory section and becomes useful immediately.

### Priority 5: Defense packaging polish (README + ensure image stays <= 10 MB)
Why:
- Prevents last-minute defense issues and proves reproducibility.
