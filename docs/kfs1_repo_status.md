# KFS_1 Repo Status vs Subject (Updated)

Snapshot date: February 22, 2026.


This status file was refreshed after the architecture migration from `x86_64` build outputs to `i386` build outputs.

## Scope of this update
=======
Scope:
- Focus on **Base (Mandatory)** epics (M0–M8).
- **Infra (Automation)** epics (I0–I2) are tracked as optional (not graded), but they make “proofs/tests” CI-friendly.
- Bonus epics are listed as deferred (not required right now).

Path/arch note:
- The spec assumes the final base target is **i386**, with artifacts like `build/kernel-i386.bin` and sources under `src/arch/i386/`.
- Until M0.1 is implemented in code, the spec explicitly allows substituting current paths/arch. This repo currently uses `arch=x86_64` naming, even though `boot.asm` is `bits 32`.

As-of snapshot (checked 2026-02-22):
- Kernel artifact present: `build/kernel-x86_64.bin` (ELF64, x86-64, ~832 bytes)
- ISO artifact present: `build/os-x86_64.iso` (~4.9 MB, bootable ISO9660)
- `src/arch/i386/` exists but is empty; active sources are under `src/arch/x86_64/` (ASM + `.ld` + `grub.cfg`)
- No C/Rust/Go/etc kernel code present (no `kmain`)
- No host-side tests/harness targets (no `make test-qemu`, `test-qemu-serial`, `test-vga`)



## Architecture Migration Summary
=======
## Epic Validation Summary (Base DoD YES/NO)


Applied changes:
- `Makefile` default target changed to `arch ?= i386`.
- NASM output changed to `-felf32`.
- Linker invocation changed to `ld -m elf_i386`.
- Run target changed to `qemu-system-i386`.
- Architecture sources now live under `src/arch/i386/`.
- `src/arch/x86_64/` was removed intentionally.

- Base Epic M0 DoD: NO
  - Spec proofs: `WP-M0.1-*`
  - Current proof: `readelf -h build/kernel-x86_64.bin` -> `Class: ELF64`, `Machine: X86-64` (subject mandates i386)
- Base Epic M1 DoD: NO (artifact exists, but rebuild/boot not provable on this machine)
  - Spec proofs: `WP-M1.1-*` + `MANUAL/AUTO-M1.1-*`
  - Current proof: `build/os-x86_64.iso` exists and is < 10 MB; `grub-mkrescue`/`qemu-system-*` are missing in PATH here
- Base Epic M2 DoD: NO
  - Spec proofs: `WP-M2.1-*`, `WP-M2.2-*`, `WP-M2.3-*`
  - Current proof: `src/arch/x86_64/boot.asm` has no stack init and no `kmain` call; ends with `hlt`
- Base Epic M3 DoD: NO
  - Spec proofs: `WP-M3.1-*`, `WP-M3.2-*`, `WP-M3.3-*`
  - Current proof: `src/arch/x86_64/linker.ld` defines only `.boot` and `.text`, and exports no layout symbols
- Base Epic M4 DoD: NO
  - Spec proofs: `WP-M4.1-*`, `WP-M4.2-*`, `WP-M4.3-*`
  - Current proof: `rg -n "\\b(kmain|main)\\b" -S src` -> no matches (no chosen-language kernel entry)
- Base Epic M5 DoD: NO
  - Spec proofs: `WP-M5.1-*` + `UT-M5.2-*` + `UT-M5.3-*`
  - Current proof: no kernel helpers/tests exist (`rg -n "\\b(strlen|strcmp|memcpy|memset)\\b" -S src` -> no matches)
- Base Epic M6 DoD: NO
  - Spec proofs: `MANUAL/AUTO-M6.*` (+ optional UT proofs)
  - Current proof: ASM writes `OK`; no screen module; `rg -n "\"42\"|\\b42\\b" -S src` -> no matches
- Base Epic M7 DoD: NO
  - Spec proofs: `WP-M7.1-*`, `WP-M7.2-*`, `WP-M7.3-*`, `WP-M7.4-*`
  - Current proof: Makefile builds only NASM, uses `nasm -felf64`, links ELF64, runs `qemu-system-x86_64`
- Base Epic M8 DoD: NO (partial deliverables only)
  - Spec proofs: `WP-M8.1-*`, `WP-M8.2-*`, `WP-M8.3-*`
  - Current proof: image exists and is small, but build/run reproducibility is blocked here and there is no `README.md`

---

## Environment Readiness (This Machine)

These tools are *not available in PATH right now* (so you cannot rebuild/run here):
- `nasm` (missing) -> `Makefile` requires it
- `qemu-system-i386` / `qemu-system-x86_64` (missing) -> cannot run `make run` / infra tests here
- `grub-mkrescue` / `grub-file` (missing) -> cannot regenerate/validate ISO here

Tools present (useful for WP/proof-style checks):
- `ld`, `as`, `readelf`, `nm`, `objdump`, `gdb`, `timeout`, `rg`

Impact:
- The repo contains prebuilt artifacts (`build/*`) that may have been built elsewhere.
- Most `MANUAL-*` and `AUTO-*` proofs from the spec are blocked until QEMU/GRUB tooling is installed.

---

## High-Level Base Status (Per Epic DoD)

Legend:
- ✅ DoD met
- ⚠️ Partial (some features done, but DoD not met)
- ❌ Not met

- Base Epic M0 (i386 + freestanding compliance): ❌
  - Evidence: `build/kernel-x86_64.bin` is ELF64 x86-64; subject mandates i386.
- Base Epic M1 (GRUB bootable image <= 10 MB): ⚠️
  - Evidence: `build/os-x86_64.iso` exists and is < 10 MB; cannot verify boot/rebuild here.
- Base Epic M2 (Multiboot header + ASM bootstrap): ❌
  - Evidence: MB2 header exists, but no stack init and no `kmain` handoff.
- Base Epic M3 (custom linker script + layout): ⚠️
  - Evidence: custom `.ld` exists and places `.multiboot_header` first, but layout is minimal and currently yields ELF64.
- Base Epic M4 (kernel in chosen language): ❌
  - Evidence: no non-ASM kernel sources exist.
- Base Epic M5 (kernel library types + helpers): ❌
  - Evidence: no types/`strlen`/`strcmp` implementations or host UTs exist.
- Base Epic M6 (screen I/O interface + prints 42): ❌
  - Evidence: ASM writes `OK` directly to VGA; no screen interface module; no `42`.
- Base Epic M7 (Makefile compiles ASM + language, links, image, run): ❌
  - Evidence: Makefile builds only ASM, uses `nasm -felf64`, links ELF64, runs x86_64 QEMU.
- Base Epic M8 (turn-in packaging): ⚠️
  - Evidence: code + Makefile exist; an image exists and is < 10 MB; no README/how-to.

---

## Infra (Automation) Status (Optional, Not Graded)

These match `Infra Epic I0–I2` in `docs/kfs1_epics_features.md`. They are not required by the PDF,
but they make Base epics provable via `AUTO-*` checks (CI-friendly).

- Infra Epic I0 (deterministic QEMU PASS/FAIL): ❌ Not started
  - Evidence: no `test-qemu` target (`make -qp | rg -n "^(test-qemu):"` finds none)
  - Blocked here anyway: `qemu-system-*` missing
- Infra Epic I1 (serial console assertions): ❌ Not started
  - Evidence: no `test-qemu-serial` target; no serial driver code
- Infra Epic I2 (VGA memory assertion harness): ❌ Not started
  - Evidence: no `test-vga` target/harness; would likely leverage `gdb` (present) once QEMU exists

---

# Base (Mandatory) Detailed Status (Per Feature)

## Base Epic M0: i386 + Freestanding Compliance

### Feature M0.1: Make i386 the explicit default target
Status: ❌ Not done
Spec proofs: `WP-M0.1-1`, `WP-M0.1-2`, `WP-M0.1-3` (+ `MANUAL/AUTO-M0.1-1`)
Evidence:
- `Makefile` defaults `arch ?= x86_64`
- `Makefile` assembles with `nasm -felf64`
- `build/kernel-x86_64.bin` is `ELF 64-bit ... x86-64`
Proof:
- `readelf -h build/kernel-x86_64.bin | rg -n "Class:|Machine:"`
- `rg -n "^arch \\?=" Makefile` and `rg -n "\\bnasm\\b.*-f" Makefile`
What’s left:
- Make i386 the explicit/primary target (`arch ?= i386`) and move sources under `src/arch/i386/`
- Produce `ELF32` objects (`nasm -f elf32`) and link with `ld -m elf_i386`
- Wire `run` to `qemu-system-i386`

### Feature M0.2: Enforce "no host libs" and "freestanding" compilation rules
Status: ⚠️ Partial / not yet applicable
Spec proofs: `WP-M0.2-1` .. `WP-M0.2-5`
Evidence:
- Current kernel is ASM-only and linked with `ld` (no libc link step).
Proof:
- `readelf -lW build/kernel-x86_64.bin | rg -n "INTERP|DYNAMIC" || echo "no INTERP/DYNAMIC"`
- `readelf -SW build/kernel-x86_64.bin | rg -n "\\.(interp|dynamic)\\b" || echo "no .interp/.dynamic"`
- `test -z "$(nm -u build/kernel-x86_64.bin)" && echo "no undefined symbols"`
What’s left:
- Once C/Rust/etc is added, enforce freestanding/no-std flags and re-run the spec’s WP checks on the i386 artifact.

### Feature M0.3: Size discipline baked into the workflow
Status: ✅ Mostly done (image size)
Spec proofs: `WP-M0.3-1`, `WP-M0.3-2`
Evidence:
- `build/os-x86_64.iso` is ~4.9 MB (< 10 MB)
Proof:
- `ISO=build/os-x86_64.iso; test $(wc -c < "$ISO") -le 10485760 && echo "ISO <= 10MB"`
What’s left:
- Keep the turned-in i386 image (expected `build/os-i386.iso`) <= 10 MB after future changes.

Epic DoD (M0) complete? ❌
- Blockers: i386 requirement not met; cannot rebuild here due to missing `nasm`.

---

## Base Epic M1: GRUB Bootable Virtual Image (<= 10 MB)

### Feature M1.1: Provide a minimal GRUB-bootable image (primary path: ISO)
Status: ⚠️ Partial (artifact exists, rebuild/verify blocked)
Spec proofs: `WP-M1.1-1`, `WP-M1.1-2`, `WP-M1.1-3` (+ `MANUAL/AUTO-M1.1-1`)
Evidence:
- `build/os-x86_64.iso` exists and is a bootable ISO9660 image
Proof:
- `file build/os-x86_64.iso`
- `test $(wc -c < build/os-x86_64.iso) -le 10485760 && echo "ISO <= 10MB"`
What’s left:
- Regenerate the ISO from sources (`grub-mkrescue`) and verify boot in QEMU once tools are available
- Produce the i386-named artifact expected by the spec (`build/os-i386.iso`)

### Feature M1.2: "Install GRUB on a virtual image" (alternate path: tiny disk image)
Status: ❌ Not done
Spec proofs: `WP-M1.2-1` (+ `MANUAL/AUTO-M1.2-1`)
Proof:
- `rg -n "^\\s*IMG\\s*:?=|\\.img\\b|grub-install\\b" -S Makefile src || echo "no disk image/grub-install path"`
What’s left:
- Add a raw disk-image build/install path (optional, but matches the subject wording exactly)

### Feature M1.3: GRUB config uses a consistent Multiboot version
Status: ⚠️ Partial (present under `src/arch/x86_64/`, not yet under `src/arch/i386/`)
Spec proofs: `WP-M1.3-1`, `WP-M1.3-2` (+ optional `WP-M1.3-3`)
Evidence:
- `src/arch/x86_64/grub.cfg` uses `multiboot2`
- `src/arch/x86_64/multiboot_header.asm` contains MB2 magic `0xe85250d6` and arch `0` (i386 protected mode)
Proof:
- `rg -n "^\\s*multiboot2\\b" -S src/arch/x86_64/grub.cfg`
- `rg -n "0xe85250d6" -S src/arch/x86_64/multiboot_header.asm`
What’s left:
- Move/copy the MB2 header + GRUB config into the i386 target directory and keep them consistent.

Epic DoD (M1) complete? ⚠️
- The image exists and is small, but local rebuild/boot verification is blocked here.

---

## Base Epic M2: Multiboot Header + ASM Boot Strap

### Feature M2.1: Valid Multiboot header placed early in the kernel image
Status: ⚠️ Partial (header present + linked early; i386 artifact not produced yet)
Spec proofs: `WP-M2.1-1`, `WP-M2.1-2` (+ `MANUAL/AUTO-M2.1-1`)
Evidence:
- Header is in `.multiboot_header`; linker script places it first in `.boot`
Proof:
- `readelf -SW build/kernel-x86_64.bin | rg -n "\\.boot|\\.multiboot_header|\\.text"`
- `nm -n build/kernel-x86_64.bin | rg -n "header_(start|end)|\\bstart\\b"`
What’s left:
- Produce the i386 kernel artifact and re-run the WP checks on `build/kernel-i386.bin`

### Feature M2.2: ASM entry point sets up a safe execution environment
Status: ❌ Not done
Spec proofs: `WP-M2.2-1`, `WP-M2.2-2` (+ `MANUAL/AUTO-M2.2-1`)
Evidence:
- `src/arch/x86_64/boot.asm` does not set up a stack
Proof:
- `rg -n "mov\\s+esp,|lea\\s+esp,|stack_(top|end)" -S src/arch/x86_64/boot.asm || echo "no stack init"`
What’s left:
- Reserve a stack region and set `esp` before calling any higher-level code

### Feature M2.3: Transfer control to a higher-level `kmain`/`main`
Status: ❌ Not done
Spec proofs: `WP-M2.3-1`, `WP-M2.3-2` (+ `MANUAL/AUTO-M2.3-1`)
Evidence:
- Boot code prints and halts; there is no `kmain`
Proof:
- `rg -n "extern\\s+kmain|call\\s+kmain" -S src/arch/x86_64/boot.asm || echo "no kmain call"`
- `rg -n "\\b(kmain|main)\\b" -S src || echo "no kmain symbol in sources"`
What’s left:
- Implement `kmain` in the chosen language and `call kmain` from ASM after stack init

Epic DoD (M2) complete? ❌

---

## Base Epic M3: Custom Linker Script + Memory Layout

### Feature M3.1: Custom `linker.ld` (do not use host scripts)
Status: ⚠️ Partial (custom script exists/used, but i386 layout/outputs not in place)
Spec proofs: `WP-M3.1-1`, `WP-M3.1-2` (+ `MANUAL/AUTO-M3.1-1`)
Evidence:
- `src/arch/x86_64/linker.ld` exists, sets `. = 1M;`, places `*(.multiboot_header)` first
- Makefile links using `-T src/arch/$(arch)/linker.ld`
Proof:
- `rg -n "ENTRY\\(|SECTIONS\\s*\\{|\\s*\\.\\s*=\\s*1M;" -S src/arch/x86_64/linker.ld`
- `rg -n "\\bld\\b.*\\s-T\\s+src/arch/\\$\\(arch\\)/linker\\.ld" -S Makefile`
What’s left:
- Produce an i386 build with `ld -m elf_i386` and ensure the script is under `src/arch/i386/`

### Feature M3.2: Provide standard sections for growth
Status: ❌ Not done
Spec proofs: `WP-M3.2-1`, `WP-M3.2-2`, `WP-M3.2-3`
Evidence:
- Linker script defines only `.boot` and `.text`
Proof:
- `rg -n "^\\s*\\.(rodata|data|bss)\\b" -S src/arch/x86_64/linker.ld || echo "missing rodata/data/bss"`
What’s left:
- Add `.rodata`, `.data`, `.bss` (and basic alignment rules)

### Feature M3.3: Export useful layout symbols
Status: ❌ Not done
Spec proofs: `WP-M3.3-1`, `WP-M3.3-2`
Proof:
- `nm -n build/kernel-x86_64.bin | rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b" || echo "no layout symbols"`
What’s left:
- Export layout symbols in the linker script and reference them from the chosen language

Epic DoD (M3) complete? ❌

ISO image:
- `file build/os-i386.iso`
- Result:
  - `ISO 9660 ... (bootable)`
- `ls -lh build/os-i386.iso`
- Result:
  - `4.9M` (<= 10 MB)

## Base Epic M4: Minimal Kernel in Your Chosen Language

### Feature M4.1: A real `kmain` entry point in the chosen language
Status: ❌ Not done
Spec proofs: `WP-M4.1-1`, `WP-M4.1-2` (+ `MANUAL/AUTO-M4.1-1`)
Proof:
- `rg -n "\\b(kmain|main)\\b" -S src || echo "no kmain/main"`
What’s left:
- Pick language (spec examples assume Rust; C is also common) and implement `kmain`

### Feature M4.2: Minimal "kernel init" sequence (even if tiny)
Status: ❌ Not done
Spec proofs: `WP-M4.2-1` (+ `MANUAL/AUTO-M4.2-1`)
Evidence:
- No chosen-language kernel exists, so there is no init sequence beyond ASM
Proof:
- `rg -n "\\b(vga|screen)_init\\b" -S src || echo "no init calls"`

### Feature M4.3: Clean halt behavior
Status: ⚠️ Partial
Spec proofs: `WP-M4.3-1` (+ `MANUAL/AUTO-M4.3-1`)
Evidence:
- Current ASM ends with `hlt`, but without a defined `cli; hlt; jmp $`-style loop
Proof:
- `rg -n "^\\s*hlt\\b|\\bcli\\b" -S src/arch/x86_64/boot.asm`
What’s left:
- Provide a consistent halt loop path for the defense build/profile (and a deterministic exit for CI via Infra I0.1)

Epic DoD (M4) complete? ❌

---

## Base Epic M5: Basic Kernel Library (Types + Helpers)

### Feature M5.1: Kernel-owned type definitions
Status: ❌ Not done
Spec proofs: `WP-M5.1-*`
Proof:
- `rg --files src | rg -n "\\.(rs|c|h|hpp)\\b" || echo "no chosen-language sources"`

### Feature M5.2: Minimal string helpers (`strlen`, `strcmp`)
Status: ❌ Not done
Spec proofs: `UT-M5.2-1`, `WP-M5.2-2`
Proof:
- `rg -n "\\b(strlen|strcmp)\\b" -S src || echo "no strlen/strcmp"`

### Feature M5.3: Minimal memory helpers (`memcpy`, `memset`)
Status: ❌ Not done
Spec proofs: `UT-M5.3-1`, `WP-M5.3-2`
Proof:
- `rg -n "\\b(memcpy|memset)\\b" -S src || echo "no memcpy/memset"`

Epic DoD (M5) complete? ❌

---

## Base Epic M6: Screen I/O Interface + Mandatory Output

### Feature M6.1: VGA text mode writer (VGA memory at `0xB8000`)
Status: ⚠️ Partial (one hard-coded store exists; no screen module)
Spec proofs: `MANUAL/AUTO-M6.1-1` (+ optional `UT-M6.1-1`)
Evidence:
- `src/arch/x86_64/boot.asm` writes a single dword to `0xB8000` (prints `OK`)
Proof:
- `rg -n "0xb8000" -S src/arch/x86_64/boot.asm`
What’s left:
- Implement a real screen module (`putc`/`puts`) callable from `kmain`

### Feature M6.2: Newline handling (basic cursor movement)
Status: ❌ Not done
Spec proofs: `UT-M6.2-1` (+ `MANUAL/AUTO-M6.2-1`)
Evidence:
- Only output logic is a single fixed store in ASM; no cursor/newline logic exists

### Feature M6.3: Mandatory output: display `42`
Status: ❌ Not done
Spec proofs: `MANUAL/AUTO-M6.3-1`, `WP-M6.3-2`
Evidence:
- Current output is `OK`, not `42`
Proof:
- `rg -n "\"42\"|\\b42\\b" -S src || echo "no 42"`
What’s left:
- Print `42` via the screen interface from `kmain` (preferred)

Epic DoD (M6) complete? ❌

---

## Base Epic M7: Makefile (ASM + Language + Link + Image)

### Feature M7.1: Compile ASM sources with the correct target format
Status: ❌ Not done
Spec proofs: `WP-M7.1-1`, `WP-M7.1-2`
Evidence:
- `Makefile` uses `nasm -felf64` (and `nasm` isn’t installed here)
Proof:
- `rg -n "\\bnasm\\b.*-f" -S Makefile`
- `command -v nasm || echo "nasm missing"`
What’s left:
- Assemble i386 objects as `elf32` and store them under `build/arch/i386/`

### Feature M7.2: Compile chosen-language sources with freestanding flags
Status: ❌ Not done
Spec proofs: `WP-M7.2-1`, `WP-M7.2-2`, `WP-M7.2-3`
Evidence:
- No chosen-language sources exist; Makefile has no C/Rust rules
Proof:
- `rg --files src | rg -n "\\.(rs|c|h|hpp)\\b" || echo "no chosen-language sources"`

### Feature M7.3: Link all objects with custom linker script
Status: ⚠️ Partial
Spec proofs: `WP-M7.3-1` (+ `MANUAL/AUTO-M7.3-1`)
Evidence:
- Links with `ld -T linker.ld`, but produces ELF64 due to inputs and missing `-m elf_i386`
Proof:
- `rg -n "\\bld\\b" -S Makefile`
- `readelf -h build/kernel-x86_64.bin | rg -n "Class:|Machine:"`
What’s left:
- Link i386 with `ld -m elf_i386 -T src/arch/i386/linker.ld ...`

### Feature M7.4: Provide standard targets (`all`, `clean`, `iso`, `run`)
Status: ✅ Done (targets exist)
Spec proofs: `WP-M7.4-1` (+ `MANUAL/AUTO-M7.4-1`)
Evidence:
- `all`, `clean`, `run`, `iso` targets exist
Proof:
- `make -qp | rg -n "^(all:|clean:|iso:|run:)" | head`
What’s left:
- Make `run`/`iso` work for i386 and add infra test targets (`test-qemu`, etc.) once QEMU/GRUB tooling is available

Epic DoD (M7) complete? ❌

---

## Base Epic M8: Turn-In Packaging (Defense-Ready)

### Feature M8.1: Turn-in artifact checklist is satisfied
Status: ⚠️ Partial
Spec proofs: `WP-M8.1-1` (+ `MANUAL-M8.1-1`)
Evidence:
- Code and Makefile are present
- A bootable image artifact exists in `build/`
Proof:
- `test -f Makefile && test -d src && echo "code+Makefile present"`
- `test -f build/os-x86_64.iso && echo "ISO present"`
What’s left:
- Make the build reproducible for i386 on a machine with required tooling

### Feature M8.2: Enforce the 10 MB upper bound
Status: ✅ Done (currently)
Spec proofs: `WP-M8.2-1`
Evidence:
- `build/os-x86_64.iso` < 10 MB
Proof:
- `test $(wc -c < build/os-x86_64.iso) -le 10485760 && echo "ISO <= 10MB"`
What’s left:
- Ensure the final i386 turn-in image stays <= 10 MB

### Feature M8.3: Minimal "how to run" notes (optional but helpful)
Status: ❌ Not done
Spec proofs: `WP-M8.3-1`, `WP-M8.3-2`
Proof:
- `test -f README.md || echo "README.md missing"`
What’s left:
- Add a minimal `README.md` quickstart (3 lines is enough)

Epic DoD (M8) complete? ⚠️

---

# Bonus (Deferred) Status

All bonus epics (B1–B5) are currently: ❌ Not started
- This is fine; bonus is only assessed after mandatory is perfect.

---

- Base Epic M3 DoD: PARTIAL
- Reason: custom linker script exists and is used, but layout is still minimal (`.boot`, `.text` only).

- Base Epic M4 DoD: NO
- Reason: no chosen-language kernel entry (`kmain`/`main`) exists yet.

- Base Epic M5 DoD: NO
- Reason: no kernel helper/type library implementation yet (`strlen`, `strcmp`, etc.).

- Base Epic M6 DoD: NO
- Reason: current ASM output writes `OK`; mandatory output is `42` via a screen interface.

Notes:
- As soon as QEMU is available, adding **Infra I0.1** (`make test-qemu`) turns “it boots” into a deterministic PASS/FAIL gate.

### Priority 2: Add chosen-language kernel entry and call it from ASM
Why:
- Subject expects ASM + chosen language, and GRUB should "call main function".

Deliverable:
- `kmain()` exists and is invoked from ASM after stack init.

## Important repository note

- Legacy pre-migration artifacts still exist in `build/` (`build/kernel-x86_64.bin`, `build/os-x86_64.iso`).
- New i386 artifacts are generated as `build/kernel-i386.bin` and `build/os-i386.iso`.

## Remaining mandatory gaps (after architecture fix)

- Add stack initialization in ASM boot entry.
- Call a chosen-language `kmain` from ASM.
- Implement a minimal screen interface and print `42`.
- Add minimal kernel helpers/types required by the subject.
- Add concise run/defense documentation.
