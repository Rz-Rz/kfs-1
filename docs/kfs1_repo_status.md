# KFS_1 Repo Status vs Subject (Done / Not Done + Priorities)

Snapshot date: February 22, 2026.

This file is an analysis of the current repository state against the backlog in:
- `docs/kfs1_epics_features.md` (baseline spec/backlog)

Scope:
- Focus on **Base (Mandatory)** epics (M0–M8).
- Bonus epics are listed as deferred (not required right now).

As-of snapshot:
- Kernel artifact present: `build/kernel-i386.bin` (ELF32, Intel 80386)
- ISO artifact present: `build/os-i386.iso` (bootable ISO9660, <= 10 MB)
- Disk-image artifact present: `build/os-i386.img` (bootable ISO9660, <= 10 MB; boots via QEMU `-drive`)
- Sources present only in ASM under `src/arch/i386/`
- No C/Rust/Go/etc kernel code present (no `kmain`)

---

## Epic Validation Summary (DoD YES/NO)

Per-epic DoD verdicts, with proof pointers. Detailed per-feature validations (each with
its own `Proof:`) start in the "Base (Mandatory) Detailed Status" section.

- Base Epic M0 DoD: ✅ YES (i386 target + no-host-libs checks pass for the current ASM-only kernel)
  - Proof: `readelf -h build/kernel-i386.bin` -> `Class: ELF32`, `Machine: Intel 80386`
  - Proof: `readelf -lW build/kernel-i386.bin` -> no `INTERP` / `DYNAMIC`
- Base Epic M1 DoD: ✅ YES (ISO + disk-image artifacts + automated boot checks)
  - Proof: `file build/os-i386.iso` -> ISO 9660 (bootable)
  - Proof: `file build/os-i386.img` -> ISO 9660 (bootable)
  - Proof: `test $(wc -c < build/os-i386.iso) -le 10485760` (<= 10 MB)
  - Proof: `test $(wc -c < build/os-i386.img) -le 10485760` (<= 10 MB)
  - Proof: `make test arch=i386` (builds + checks ISO/IMG size/type and boots both test ISO and test IMG headlessly)
- Base Epic M2 DoD: ❌ NO
  - Proof: `src/arch/i386/boot.asm` has no stack init and no `kmain` call; ends with `hlt`
- Base Epic M3 DoD: ❌ NO
  - Proof: `src/arch/i386/linker.ld` defines only `.boot` and `.text`, and exports no layout symbols
- Base Epic M4 DoD: ❌ NO
  - Proof: `rg -n "\\b(kmain|main)\\b" -S src` -> no matches (no chosen-language kernel entry)
- Base Epic M5 DoD: ❌ NO
  - Proof: `rg -n "\\b(strlen|strcmp|memcpy|memset)\\b" -S src` -> no matches (no kernel library helpers)
- Base Epic M6 DoD: ❌ NO
  - Proof: `src/arch/i386/boot.asm` prints `OK`; `rg -n "\\b42\\b|\\\"42\\\"" -S src` -> no matches
- Base Epic M7 DoD: ⚠️ PARTIAL (Makefile builds ASM+ISO+IMG and runs QEMU; missing chosen-language build rules)
  - Proof: Makefile compiles ASM/links/ISO/IMG/runs, but no chosen-language build rules exist yet
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
- Base Epic M2 (Multiboot header + ASM bootstrap): ❌
- Base Epic M3 (custom linker script + layout): ❌
- Base Epic M4 (kernel in chosen language): ❌
- Base Epic M5 (kernel library types + helpers): ❌
- Base Epic M6 (screen I/O interface + prints 42): ❌
- Base Epic M7 (Makefile compiles ASM + language, links, image, run): ⚠️
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
Status: ⚠️ Partial / not yet exercised by a chosen language
Evidence:
- Current kernel is ASM-only and linked with `ld` (no libc link step).
- Artifact is statically linked and has no dynamic loader segments/sections.
Proof:
- `readelf -lW build/kernel-i386.bin | rg -n "INTERP|DYNAMIC" || echo "no INTERP/DYNAMIC"`
- `readelf -SW build/kernel-i386.bin | rg -n "\\.(interp|dynamic)\\b" || echo "no .interp/.dynamic"`
- `test -z "$(nm -u build/kernel-i386.bin)" && echo "no undefined symbols"`
What’s left:
- Once C/Rust/etc is added, enforce freestanding/no-std flags and re-run the checks on the same i386 artifact.

### Feature M0.3: Size discipline baked into workflow
Status: ✅ Mostly done (image size)
Evidence:
- `build/os-i386.iso` is <= 10 MB
Proof:
- `ISO=build/os-i386.iso; test $(wc -c < "$ISO") -le 10485760 && echo "ISO <= 10MB"`

Epic DoD (M0) complete? ✅

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
- `make test arch=i386` (includes build + checks + `scripts/test-qemu.sh i386 drive`)

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
Status: ⚠️ Partial (header exists + linked early; bootstrap remains minimal)
Evidence:
- Header lives in `.multiboot_header`; linker script places it first in `.boot`
Proof:
- `readelf -SW build/kernel-i386.bin | rg -n "\\.boot|\\.multiboot_header|\\.text"`
- `nm -n build/kernel-i386.bin | rg -n "header_(start|end)|\\bstart\\b"`

### Feature M2.2: ASM entry point sets up a safe execution environment
Status: ❌ Not done
Evidence:
- `src/arch/i386/boot.asm` does not set up a stack
Proof:
- `rg -n "mov\\s+esp,|lea\\s+esp,|stack_(top|end)" -S src/arch/i386/boot.asm || echo "no stack init"`
What’s left:
- Reserve a stack region and set `esp` before calling any higher-level code

### Feature M2.3: Transfer control to a higher-level `kmain`/`main`
Status: ❌ Not done
Evidence:
- Boot code prints and halts; there is no `kmain`
Proof:
- `rg -n "extern\\s+kmain|call\\s+kmain" -S src/arch/i386/boot.asm || echo "no kmain call"`
- `rg -n "\\b(kmain|main)\\b" -S src || echo "no kmain symbol in sources"`

Epic DoD (M2) complete? ❌

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
Status: ❌ Not done
Evidence:
- Linker script defines only `.boot` and `.text`
Proof:
- `rg -n "^\\s*\\.(rodata|data|bss)\\b" -S src/arch/i386/linker.ld || echo "missing rodata/data/bss"`

### Feature M3.3: Export useful layout symbols
Status: ❌ Not done
Proof:
- `nm -n build/kernel-i386.bin | rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b" || echo "no layout symbols"`

Epic DoD (M3) complete? ❌

---

## Base Epic M4: Minimal Kernel in Your Chosen Language

Status: ❌ Not started
Proof:
- `rg --files src | rg -n "\\.(rs|c|h|hpp)\\b" || echo "no chosen-language sources"`

---

## Base Epic M5: Basic Kernel Library (Types + Helpers)

Status: ❌ Not started

---

## Base Epic M6: Screen I/O Interface + Mandatory Output

### Feature M6.3: Mandatory output: display `42`
Status: ❌ Not done
Evidence:
- Current output is `OK` in ASM
Proof:
- `rg -n "0xb8000" -S src/arch/i386/boot.asm`
- `rg -n "\\b42\\b|\\\"42\\\"" -S src || echo "no 42 yet"`

---

## Base Epic M7: Makefile must compile all sources (ASM + chosen language), link, image, run

Status: ⚠️ Partial
Evidence:
- Makefile assembles ASM, links i386, builds ISO, and runs QEMU.
- There are no compile rules for a chosen-language kernel yet.
Proof:
- `make -n iso`
- `rg --files src | rg -n "\\.(rs|c|h|hpp)\\b" || echo "no chosen-language sources"`

---

## Base Epic M8: Turn-in Packaging

Status: ⚠️ Partial
Evidence:
- ISO exists and is <= 10 MB: `build/os-i386.iso`
What’s left:
- Update `README.md` with the expected output 42 once the screen interface is implemented.

---

## Infra Automation Status

Status: ✅ In place
Evidence:
- `make test` rebuilds the container toolchain image each run
- `make test` verifies the required tools exist in the container
- `make test` validates M1 artifacts and boot gates
  - Build + check release ISO (type + <= 10 MB)
  - Build + check release disk image (type + <= 10 MB)
  - Boot test ISO via GRUB in QEMU headless and exit PASS/FAIL
  - Boot test disk image via QEMU `-drive` and exit PASS/FAIL
Proof:
- `make test`
- `make test KFS_TEST_FORCE_FAIL=1`
