# KFS_1 - Epics and Features (Base vs Bonus)

Source: `docs/subject.pdf` (KFS_1: "Grub, boot and screen", Version 1).

This document is a requirements-to-backlog translation split into:
- **Base (Mandatory)**: what you must deliver
- **Bonus (Deferred)**: explicitly *not* doing now, but captured for later

Repo decision (language):
- Chosen language for the kernel code in this repo: **Rust** (freestanding / `#![no_std]`).

Each epic has:
- Multiple features
- Acceptance criteria and validation hints
- A per-epic **Definition of Done (DoD)**

---

# Infrastructure (Automation) Epics — Not graded, but makes KFS_1 provable

These epics exist to replace “I saw it in QEMU” with **automated, repeatable proofs**.
They are optional for the subject, but extremely useful for TDD and CI.

## Infra Epic I0: Deterministic QEMU PASS/FAIL via `isa-debug-exit`

### Feature I0.1: `make test-qemu` runs headless and exits with PASS/FAIL
Implementation tasks:
- Add a `test-qemu` Make target that runs QEMU headless with:
  - `-device isa-debug-exit,iobase=0xf4,iosize=0x04`
  - no GUI (`-nographic`) and a hard timeout (host-side)
- Add a tiny “test signal” in the kernel (ASM or Rust) that writes a byte to port `0xF4`
  to indicate PASS/FAIL (e.g., `0x10` = pass, `0x11` = fail).
- Use this as the end-of-test terminator so CI never hangs.

Acceptance criteria:
- A passing boot/test run makes QEMU exit deterministically with a “pass” exit status.
- A failing assertion makes QEMU exit deterministically with a “fail” exit status.
- The harness has a timeout so a hang becomes a test failure.

Implementation scope:
- `MAKE` + (`ASM` or `RUST`) + `AUTOMATION`

Proof / tests (definition of done):
- WP-I0.1-1 (QEMU uses isa-debug-exit): `make -n test-qemu arch=i386 | rg -n "isa-debug-exit.*iobase=0xf4"`
- WP-I0.1-2 (PASS gives expected exit code): `make test-qemu arch=i386; echo $?` (expect the configured PASS code)
- WP-I0.1-3 (hang is caught): run the harness with a tiny timeout and confirm it fails when the kernel never exits

Definition of Done (I0):
- `make test-qemu` is a one-command, headless PASS/FAIL gate suitable for CI.

---

## Infra Epic I1: Serial console for scalable automated assertions

### Feature I1.1: Kernel logs to COM1 and host tests can assert on output
Implementation tasks:
- Implement a minimal COM1 serial writer (port `0x3F8`) in the kernel:
  - init baud/line control
  - `serial_putc`/`serial_puts`
- Add a QEMU run mode that routes COM1 to stdout:
  - `-nographic -serial stdio`
- Add a host-side smoke test that boots and asserts log lines (e.g., `KMAIN_OK`, `SCREEN_OK`).

Acceptance criteria:
- Boot prints at least one stable line from `kmain` to the host stdout.
- Host automation can assert on that output without GUI/VGA scraping.

Implementation scope:
- `RUST` (or `ASM`) + `MAKE` + `AUTOMATION`

Proof / tests (definition of done):
- WP-I1.1-1 (QEMU serial routed): `make -n test-qemu-serial arch=i386 | rg -n "(-serial stdio|-nographic)"`
- WP-I1.1-2 (output contains marker): `make test-qemu-serial arch=i386 | rg -n "KMAIN_OK"`
- WP-I1.1-3 (structured markers): markers are fixed tokens (not free-form sentences) so tests don’t become brittle

Definition of Done (I1):
- Serial output is a stable “assertion channel” that scales as you add features.

---

## Infra Epic I2: VGA text buffer assertion (no GUI required)

### Feature I2.1: Headless test can assert VGA memory at `0xB8000`
Implementation tasks:
- Keep the kernel’s visible output in VGA text mode (as per subject).
- Add a headless harness that boots QEMU and then reads guest memory at `0xB8000`
  (e.g., via QEMU gdbstub `-S -s` + a host script) to assert the expected characters.

Acceptance criteria:
- A host test can prove “`42` is on screen” without any GUI or screenshot.

Implementation scope:
- `AUTOMATION` (+ kernel output in `ASM`/`RUST`)

Proof / tests (definition of done):
- WP-I2.1-1 (gdbstub enabled): `make -n test-vga arch=i386 | rg -n "(-S\\s+-s|gdb)"`
- WP-I2.1-2 (VGA bytes asserted): the harness reads `0xB8000` and asserts it contains `0x34`/`0x32` as the character bytes (with your chosen attribute)

Definition of Done (I2):
- “Print 42” can be asserted headlessly by reading VGA memory.

---

## Infra Epic I3: Reproducible Dev Environment

Goal:
- Make builds and tests reproducible across host OSes by standardizing the toolchain entrypoints

Motivation:
- Tool and package names differ across distros
- Some machines do not have the required tooling installed

### Feature I3.1: Containerized dev toolchain
Implementation tasks:
- Ship a repo local container definition that installs the full toolchain
  - `nasm`, `binutils`, `make`
  - `qemu-system-i386`
  - `grub-mkrescue`, `xorriso`, `mtools`
- Add Make targets that work with Docker or Podman
  - `make container-image`
  - `make container-env-check`
  - `make dev`
  - `make test`

Acceptance criteria:
- Fedora and Ubuntu WSL can both run `make test` and get the same PASS or FAIL behavior
- CI runs `make test` in a headless container environment

Implementation scope:
- `MAKE` + `AUTOMATION`

Proof and tests:
- WP-I3.1-1 engine works: `make container-env-check`
- WP-I3.1-2 daily gate works: `make test`

Definition of Done (I3):
- There is a known good container path to build and run tests that is independent of host distro

---

## Verification Conventions (Used In This Backlog)

To make this backlog **TDD-friendly**, each feature below gets appended metadata:

- **Implementation scope**: what “language / layer” owns the work:
  - `ASM` (boot + multiboot header)
  - `LD` (GNU ld linker script)
  - `MAKE` (Makefile/build targets)
  - `RUST` (chosen language kernel code; if you choose C instead, translate the tests)
  - `AUTOMATION` (host scripts that validate artifacts; bash/python)
- **Proof / tests**: a command-line definition of “done” for that feature.
  - `WP-*` = workflow proof (artifact inspection commands)
  - `MANUAL-*` = manual proof (QEMU boot observation)
  - `UT-*` = host unit test (pure logic like `strlen`, cursor math)

Command assumptions:
- Examples assume the **final base target** is i386 (per subject), so artifacts are named like `build/kernel-i386.bin` and sources live under `src/arch/i386/`.
- Until Feature **M0.1** is implemented in code, you may need to substitute current paths/arch (e.g., `arch=x86_64`, `src/arch/x86_64/`).

---

## Base vs Bonus Rule (From The Subject)

Bonus work is assessed **only if** the mandatory part is **perfect** (fully implemented,
works without malfunctioning). If any mandatory requirement is missing, bonus is not
evaluated.

---

## Coverage Check (Nothing Forgotten)

Mandatory requirements in the PDF and where they are covered:
- "i386 (x86) architecture is mandatory" -> Base Epic M0
- "Install GRUB on a virtual image" -> Base Epic M1 (ISO path + optional disk-image path)
- "Write ASM boot code that handles multiboot header" -> Base Epic M2
- "Use GRUB to init and call main function of the kernel" -> Base Epic M2 + Base Epic M4
- "Write basic kernel code of the chosen language" -> Base Epic M4
- "Compile with correct flags; no host libs; link it to make it bootable" -> Base Epic M0 + Base Epic M3 + Base Epic M7
- "Create a linker file with GNU ld (no host .ld)" -> Base Epic M3
- "Write helpers like kernel types or basic functions (strlen, strcmp, ...)" -> Base Epic M5
- "Code the interface between your kernel and the screen" -> Base Epic M6
- 'Display "42" on the screen' -> Base Epic M6
- "Makefile must compile all source files with correct flags (ASM + other language)" -> Base Epic M7
- "Work must not exceed 10 MB" + "turn in a basic virtual image (10 MB upper bound)" -> Base Epic M1 + Base Epic M8
- "Turn-in: code + Makefile + basic virtual image" -> Base Epic M8

Bonus items in the PDF and where they are covered:
- Scroll + cursor -> Bonus Epic B1
- Colors -> Bonus Epic B2
- printf/printk -> Bonus Epic B3
- Keyboard entries and print them -> Bonus Epic B4
- Multiple screens + shortcuts -> Bonus Epic B5

---

## Notes About This Repo (Current Gaps vs The PDF)

This repo already builds a GRUB ISO and contains a Multiboot2 header.
Current state vs KFS_1 requirements:
- Architecture/toolchain alignment is now fixed for i386:
  - Sources are under `src/arch/i386`.
  - `Makefile` uses `nasm -felf32`, `ld -m elf_i386`, and `qemu-system-i386`.
  - Proof (local commands):
  - `readelf -h build/kernel-i386.bin` -> `Class: ELF32`, `Machine: Intel 80386`
  - `file build/arch/i386/boot.o` -> `ELF 32-bit LSB relocatable, Intel 80386`
- Mandatory functional gaps still open:
  - ASM entry does not initialize a stack or transfer control to `kmain` yet.
  - Current output is still `OK`; KFS_1 requires displaying `42` via a screen interface.

---

## Global Constraints (Base and Bonus)

- Architecture: i386/x86 (32-bit) mandatory.
- No host dependencies: do not link against libc/host runtime.
- Linking: `ld` is allowed; host linker scripts are not; ship your own `.ld`.
- Boot: GRUB + Multiboot (v1 or v2) with a valid header in the kernel image.
- Size: do not exceed 10 MB for the "virtual image" you turn in (and practically keep
  artifacts minimal).

---

# Base (Mandatory) Epics

## Base Epic M0: i386 + Freestanding Compliance

### Feature M0.1: Make i386 the explicit default target
Implementation tasks:
- Use an explicit arch name that matches the subject (recommended: `i386`).
- Ensure assembler output is 32-bit (`nasm -felf32`).
- Ensure linker mode is 32-bit (`ld -m elf_i386`).
- Ensure QEMU run target matches (`qemu-system-i386`).

Repo implementation note (where this is wired):
- `Makefile` assembles with `nasm -felf32`, links with `ld -m elf_i386`, and runs with `qemu-system-i386`.

Subject references:
- III.4 Architecture (i386 mandatory)
- IV.0.2 Makefile (rules for ASM + chosen language)

Acceptance criteria:
- `file build/kernel-*.bin` indicates a 32-bit kernel artifact.
- Boot works under `qemu-system-i386`.

Implementation scope:
- `MAKE` + `ASM` + `LD` (+ `AUTOMATION` optional for checks)

Proof / tests (definition of done):
- WP-M0.1-1 (ELF32 + i386): `KERNEL=build/kernel-i386.bin; readelf -h "$KERNEL" | rg -q "Class:\\s+ELF32" && readelf -h "$KERNEL" | rg -q "Machine:\\s+Intel 80386"`
- WP-M0.1-2 (object format): `file build/arch/i386/*.o | rg -q "ELF 32-bit"`
- WP-M0.1-3 (QEMU target wired): `make -n run arch=i386 | rg -q "qemu-system-i386"`
- MANUAL-M0.1-1 (boots): `make run arch=i386` and confirm the kernel reaches its entry behavior (e.g., prints or halts as expected). (Automation: prefer AUTO-M0.1-1)
- AUTO-M0.1-1 (preferred for CI): use **Infra I0.1** (isa-debug-exit PASS/FAIL) to assert “kernel reached checkpoint”; use **Infra I1.1** only if you want richer boot logs

### Feature M0.2: Enforce "no host libs" and "freestanding" compilation rules
Implementation tasks (adapt to chosen language):
- Compile freestanding and disable default libs/startup objects.
- Avoid exceptions/RTTI/new/delete until you have a kernel allocator/runtime.

Technical rationale:
- See `docs/m0_2_freestanding_proofs.md` for why the ELF inspection checks are meaningful proofs of “no host libs”.

Repo enforcement note:
- The hard gate is `make test arch=i386`, which runs `scripts/check-m0.2-freestanding.sh` on the freshly built
  test kernel (`build/kernel-i386-test.bin`).
- The script requires the symbol `kfs_rust_marker` so the checks are enforced on an **ASM + Rust** linked kernel
  artifact (not ASM-only).

Acceptance criteria:
- Kernel artifact is not dynamically linked (no `.interp`, no `.dynamic`).
- No unresolved external symbols from libc at link time.

Implementation scope:
- `RUST` (freestanding build flags) + `LD` (+ `MAKE`)

Subject references:
- III.2.2 Flags (no dependencies / no host libs; `-nostdlib`, `-nodefaultlibs`, etc.)
- III.3 Linking (use `ld` but not host `.ld`; ship your own linker script)

Proof / tests (definition of done):
- WP-M0.2-1 (no PT_INTERP segment): `KERNEL=build/kernel-i386.bin; ! readelf -lW "$KERNEL" | rg -n "INTERP"`
- WP-M0.2-2 (no .interp/.dynamic sections): `KERNEL=build/kernel-i386.bin; ! readelf -SW "$KERNEL" | rg -n "\\.(interp|dynamic)\\b"`
- WP-M0.2-3 (no undefined symbols): `KERNEL=build/kernel-i386.bin; test -z "$(nm -u "$KERNEL")"`
- WP-M0.2-4 (no libc/loader strings): `KERNEL=build/kernel-i386.bin; ! strings "$KERNEL" | rg -ni "(glibc|libc\\.so|ld-linux)"`
- WP-M0.2-5 (build flags present; configuration proof): `rg -n "(ffreestanding|nostdlib|fno-builtin|panic=abort|#!\\[no_std\\])" -S .`

### Feature M0.3: Size discipline baked into the workflow
Implementation tasks:
- Prefer stripped/minimal artifacts for the image.
- Avoid committing large generated files besides the required "virtual image".

Acceptance criteria:
- Produced virtual image is <= 10 MB.

Implementation scope:
- `MAKE` (+ optional `AUTOMATION` checks)

Proof / tests (definition of done):
- WP-M0.3-1 (ISO <= 10 MB): `ISO=build/os-i386.iso; test $(wc -c < "$ISO") -le 10485760`
- WP-M0.3-2 (kernel small / sanity): `KERNEL=build/kernel-i386.bin; ls -lh "$KERNEL" "$ISO"`

### Definition of Done (M0)
- From a clean tree: `make clean && make && make iso && make run` boots on i386.
- Kernel build is demonstrably freestanding (no host libc dependency).
- Artifact/image sizes meet the 10 MB requirement.

---

## Base Epic M1: GRUB Bootable Virtual Image (<= 10 MB)

### Feature M1.1: Provide a minimal GRUB-bootable image (primary path: ISO)
Implementation tasks:
- Build an ISO using `grub-mkrescue` containing:
  - `/boot/kernel.bin` (or kernel ELF, depending on config)
  - `/boot/grub/grub.cfg`
- Keep ISO tree minimal.

Acceptance criteria:
- `build/os-*.iso` exists and is <= 10 MB.
- Booting the ISO reaches the kernel entry point.

Implementation scope:
- `MAKE` + `AUTOMATION` (ISO tree) + `GRUB` config (data file)

Proof / tests (definition of done):
- WP-M1.1-1 (ISO exists): `ISO=build/os-i386.iso; test -f "$ISO"`
- WP-M1.1-2 (ISO is bootable ISO9660): `ISO=build/os-i386.iso; file "$ISO" | rg -q "ISO 9660"`
- WP-M1.1-3 (ISO <= 10 MB): `ISO=build/os-i386.iso; test $(wc -c < "$ISO") -le 10485760`
- MANUAL-M1.1-1 (boots to kernel): `qemu-system-i386 -cdrom build/os-i386.iso -no-reboot -no-shutdown` and confirm the kernel runs (reaches `start` / later `kmain`). (Automation: prefer AUTO-M1.1-1)
- AUTO-M1.1-1 (preferred for CI): replace the visual check with **Infra I0.1** (“kernel exits PASS”) and keep this MANUAL check for defense-only

### Feature M1.2: "Install GRUB on a virtual image" (alternate path: tiny disk image)
This is optional if your evaluation accepts an ISO, but it exactly matches the wording
in the subject and can reduce ambiguity during defense.

Repo implementation note:
- This repo implements the “disk image” path as an `.img` file that is **ISO content** and is booted via QEMU’s
  `-drive format=raw,file=...` path.
- This avoids brittle `grub-install`/partitioning flows inside containers, while still producing a hand-off image
  file that boots to the kernel.

Implementation tasks (one possible approach):
- Create a small raw image file.
- Partition/format it minimally.
- Install GRUB to it and place kernel + `grub.cfg`.

Acceptance criteria:
- The disk image boots via QEMU and reaches the kernel.
- Image is <= 10 MB.

Implementation scope:
- `AUTOMATION` (image creation) + `GRUB` tooling + `MAKE`

Proof / tests (definition of done):
- WP-M1.2-1 (image exists + size): `IMG=build/os-i386.img; test -f "$IMG" && test $(wc -c < "$IMG") -le 10485760`
- MANUAL-M1.2-1 (boots): `qemu-system-i386 -drive format=raw,file=build/os-i386.img -no-reboot -no-shutdown` and confirm it reaches the kernel. (Automation: prefer AUTO-M1.2-1)
- AUTO-M1.2-1 (preferred for CI): use **Infra I0.1** as the “boots far enough” gate for the disk-image path
  - In this repo: `make img-test arch=i386 && bash scripts/test-qemu.sh i386 drive` (PASS via isa-debug-exit)

### Feature M1.3: GRUB config uses a consistent Multiboot version
Implementation tasks:
- Pick Multiboot v1 or v2 and keep it consistent:
  - Multiboot2: `multiboot2 /boot/kernel.bin` and MB2 header magic `0xe85250d6`.

Acceptance criteria:
- GRUB does not print Multiboot magic/header errors during boot.

Implementation scope:
- `ASM` (Multiboot header) + `GRUB` config (data) + `LD` placement

Proof / tests (definition of done):
- WP-M1.3-1 (GRUB entry uses multiboot2): `rg -n "^\\s*multiboot2\\b" -S src/arch/i386/grub.cfg`
- WP-M1.3-2 (MB2 magic present in sources): `rg -n "0xe85250d6" -S src/arch/i386/multiboot_header.asm`
- WP-M1.3-3 (kernel recognized by grub-file, if available): `KERNEL=build/kernel-i386.bin; grub-file --is-x86-multiboot2 "$KERNEL"`
- MANUAL-M1.3-1 (no GRUB errors): boot ISO in QEMU and confirm GRUB does not display multiboot header errors. (Automation: prefer AUTO-M1.3-1)
- AUTO-M1.3-1 (usually enough): if **Infra I0.1** reaches “kernel PASS”, GRUB necessarily loaded the kernel successfully; combine with WP-M1.3-3 for an automated “multiboot2 recognized” check (full GRUB message capture is optional)

### Definition of Done (M1)
- You can hand someone the produced image file (ISO or disk image) and they can boot
  it in QEMU and reach the kernel without manual GRUB setup.
- Image is <= 10 MB.

---

## Base Epic M2: Multiboot Header + ASM Boot Strap

### Feature M2.1: Valid Multiboot header placed early in the kernel image
Implementation tasks:
- Put the header in a dedicated section (e.g., `.multiboot_header`).
- Ensure the linker script places it early enough for GRUB to find it.
- Ensure header length and checksum are correct.

Acceptance criteria:
- GRUB recognizes the kernel via `multiboot`/`multiboot2` and loads it reliably.

Implementation scope:
- `ASM` + `LD` (section placement)

Proof / tests (definition of done):
- WP-M2.1-1 (section exists + early placement): `KERNEL=build/kernel-i386.bin; readelf -SW "$KERNEL" | rg -n "\\.boot|\\.multiboot_header"`
- WP-M2.1-2 (magic at .boot start): `KERNEL=build/kernel-i386.bin; OFF=$(readelf -S "$KERNEL" | awk '$3==\".boot\"{print $6; exit}'); test -n \"$OFF\" && od -An -tx4 -N4 -j $((16#$OFF)) \"$KERNEL\" | tr -d \" \\n\" | rg -q \"^e85250d6$\"`
- MANUAL-M2.1-1 (GRUB accepts it): `make run arch=i386` and confirm no multiboot header errors. (Automation: prefer AUTO-M2.1-1)
- AUTO-M2.1-1 (preferred for CI): use **Infra I0.1** as “GRUB accepted header and entered kernel”; keep this MANUAL check for defense-only

### Feature M2.2: ASM entry point sets up a safe execution environment
Implementation tasks:
- Define the entry symbol that GRUB jumps to (e.g., `start`).
- Initialize a stack.
- Optionally clear direction flag (`cld`) and ensure interrupts are in a known state.

Acceptance criteria:
- Kernel doesn't crash due to missing stack or undefined state.

Implementation scope:
- `ASM`

Proof / tests (definition of done):
- WP-M2.2-1 (stack init exists in source): `rg -n "mov\\s+esp,|lea\\s+esp,|stack_(top|end)" -S src/arch/i386/boot.asm`
- WP-M2.2-2 (symbol exists in artifact): `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "stack_(top|end)"`
- MANUAL-M2.2-1 (no immediate crash): boot in QEMU with `-no-reboot -no-shutdown` and confirm it does not reset/triple-fault immediately. (Automation: prefer AUTO-M2.2-1)
- AUTO-M2.2-1 (preferred for CI): make the kernel emit PASS via **Infra I0.1** only *after* stack init + `kmain` call; a triple-fault/hang becomes a harness timeout failure

### Feature M2.3: Transfer control to a higher-level `kmain`/`main`
Implementation tasks:
- Provide a callable function in the chosen language (`kmain` recommended).
- Ensure calling convention matches i386 cdecl-like assumptions.
- If `kmain` returns, halt cleanly (`cli; hlt; jmp $`).

Acceptance criteria:
- You can prove control flow reached `kmain` (e.g., print from `kmain`).

Implementation scope:
- `ASM` (call site) + `RUST` (kmain)

Proof / tests (definition of done):
- WP-M2.3-1 (boot.asm calls kmain): `rg -n "extern\\s+kmain|call\\s+kmain" -S src/arch/i386/boot.asm`
- WP-M2.3-2 (kmain symbol exists in kernel): `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "\\bkmain\\b"`
- MANUAL-M2.3-1 (observable from kmain): boot and confirm output is produced from `kmain` (e.g., prints `42` via the screen module). (Automation: prefer AUTO-M2.3-1)
- AUTO-M2.3-1 (preferred for CI): add a stable serial marker (e.g., `KMAIN_OK`) and assert it via **Infra I1.1**, then exit PASS via **Infra I0.1**

### Definition of Done (M2)
- Boot sequence is deterministic:
  - GRUB loads kernel -> ASM entry runs -> `kmain` runs -> kernel halts cleanly.

---

## Base Epic M3: Custom Linker Script + Memory Layout

### Feature M3.1: Custom `linker.ld` (do not use host scripts)
Implementation tasks:
- `ENTRY(start)` (or your chosen entry).
- Load address starts at 1 MiB (`. = 1M;`).
- Section ordering puts Multiboot header early.

Acceptance criteria:
- Kernel links via `ld -T linker.ld` and boots under GRUB.

Implementation scope:
- `LD` (+ `MAKE`)

Proof / tests (definition of done):
- WP-M3.1-1 (linker script exists + has required directives): `rg -n "^(ENTRY\\(|SECTIONS\\s*\\{|\\s*\\.\\s*=\\s*1M;)" -S src/arch/i386/linker.ld`
- WP-M3.1-2 (build uses your script, not host defaults): `make -n all arch=i386 | rg -n "\\bld\\b" | rg -q "\\s-T\\s+src/arch/i386/linker\\.ld"`
- MANUAL-M3.1-1 (boots): `make run arch=i386` and confirm GRUB loads the kernel and reaches `start`. (Automation: prefer AUTO-M3.1-1)
- AUTO-M3.1-1 (preferred for CI): use **Infra I0.1** as the boot gate (if kernel exits PASS, link+load address+entry all worked)

### Feature M3.2: Provide standard sections for growth
Implementation tasks:
- Define `.text`, `.rodata`, `.data`, `.bss`.
- Ensure `.bss` is allocated properly (and can be zeroed later if needed).

Acceptance criteria:
- Adding a C/Rust module does not require reworking the whole linker layout.

Implementation scope:
- `LD` (+ `RUST`)

Proof / tests (definition of done):
- WP-M3.2-1 (linker defines standard output sections): `rg -n "^\\s*\\.(text|rodata|data|bss)\\b" -S src/arch/i386/linker.ld`
- WP-M3.2-2 (artifact contains the expected sections): `KERNEL=build/kernel-i386.bin; readelf -SW "$KERNEL" | rg -n "\\.(text|rodata|data|bss)\\b"`
- WP-M3.2-3 (growth smoke test): add a tiny module that puts data in `.rodata` and `.bss`, then `make arch=i386` still links without linker-script edits (TDD target for this feature)

### Feature M3.3: Export useful layout symbols
Implementation tasks:
- Export symbols like `kernel_start`, `kernel_end`, `bss_start`, `bss_end` (names flexible).

Acceptance criteria:
- Other kernel code can reference those symbols without hardcoding addresses.

Implementation scope:
- `LD` (+ `RUST`)

Proof / tests (definition of done):
- WP-M3.3-1 (symbols exist in artifact): `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b"`
- WP-M3.3-2 (referenced from Rust): `rg -n "extern\\s+\"C\"\\s*\\{[^}]*\\b(kernel_start|kernel_end|bss_start|bss_end)\\b" -S src`

### Definition of Done (M3)
- Linker script is self-contained, reviewed, and demonstrably used in the build.
- Section layout is stable enough to add more code without fragile hacks.

---

## Base Epic M4: Minimal Kernel in Your Chosen Language

### Feature M4.1: A real `kmain` entry point in the chosen language
Implementation tasks:
- Implement `kmain` in C/C++/Rust/etc.
- Avoid language runtime features that require an allocator or OS support.

Acceptance criteria:
- `kmain` runs after boot and can call screen output functions.

Implementation scope:
- `RUST` (+ `ASM` call site)

Proof / tests (definition of done):
- WP-M4.1-1 (kmain exists as a symbol): `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "\\bkmain\\b"`
- WP-M4.1-2 (boot calls into it): `objdump -d build/kernel-i386.bin | rg -n "call.*kmain"`
- MANUAL-M4.1-1 (observable behavior from kmain): boot in QEMU and confirm output is produced by `kmain` (e.g., prints via the screen module). (Automation: prefer AUTO-M4.1-1)
- AUTO-M4.1-1 (preferred for CI): print `KMAIN_OK` on serial (Infra I1.1) and exit PASS (Infra I0.1) right after `kmain` runs

### Feature M4.2: Minimal "kernel init" sequence (even if tiny)
Implementation tasks:
- Establish a minimal init pattern (e.g., `kmain` calls `vga_init`, then prints).
- Keep it structured for later KFS modules.

Acceptance criteria:
- Boot-to-output flow is in the chosen language, not only ASM.

Implementation scope:
- `RUST` (init orchestration)

Proof / tests (definition of done):
- WP-M4.2-1 (init sequence exists in code): `rg -n "\\bkmain\\b|\\b(vga|screen)_init\\b" -S src`
- MANUAL-M4.2-1 (prints from language path): boot and confirm the printed output is produced via Rust screen calls (not a hard-coded ASM VGA store). (Automation: prefer AUTO-M4.2-1)
- AUTO-M4.2-1 (preferred for CI): log ordered serial markers like `INIT_OK` then `SCREEN_OK` (Infra I1.1), and exit PASS (Infra I0.1); keep MANUAL only if you need the on-screen defense demo

### Feature M4.3: Clean halt behavior
Implementation tasks:
- Provide a consistent halt function (e.g., `cpu_halt_forever()`).

Acceptance criteria:
- After printing, kernel halts without rebooting or triple faulting.

Implementation scope:
- `ASM` or `RUST` (but must compile to `cli/hlt` loop)

Proof / tests (definition of done):
- WP-M4.3-1 (halt loop exists in sources): `rg -n "(cli\\s*;\\s*)?hlt" -S src/arch/i386/boot.asm src`
- MANUAL-M4.3-1 (no reboot): run QEMU with `-no-reboot -no-shutdown` and confirm it does not reset; it halts as intended. (Automation: prefer AUTO-M4.3-1)
- AUTO-M4.3-1 (preferred for CI): don’t “hlt forever” in CI—exit PASS via **Infra I0.1** at end-of-test; keep `hlt` loop for the defense build/profile

### Definition of Done (M4)
- Kernel "main" is in the chosen language, reachable and stable.
- Kernel does not rely on host runtime libraries.

---

## Base Epic M5: Basic Kernel Library (Types + Helpers)

### Feature M5.1: Kernel-owned type definitions
Implementation tasks:
- Define fixed-width integer types and `size` types in kernel headers/modules.

Acceptance criteria:
- Kernel code compiles without pulling in host-dependent headers.

Implementation scope:
- `RUST` (kernel library)

Proof / tests (definition of done):
- WP-M5.1-1 (no std in kernel code): `rg -n "\\bstd::|extern\\s+crate\\s+std\\b" -S src | rg -v "tests?/|host"`
- WP-M5.1-2 (types exist): `rg -n "\\b(u8|u16|u32|i32|usize)\\b" -S src | rg -n "type|pub type|struct"`
- WP-M5.1-3 (build proof): `make arch=i386` succeeds with freestanding settings (no host headers/stdlib linked into the kernel)

### Feature M5.2: Minimal string helpers (`strlen`, `strcmp`)
Implementation tasks:
- Implement `strlen` and `strcmp` (explicitly mentioned by the subject).

Acceptance criteria:
- Helpers behave correctly for typical strings used by your screen interface.

Implementation scope:
- `RUST` (pure helper functions; unit-testable on host)

Proof / tests (definition of done):
- UT-M5.2-1 (host unit tests): create `tests/host_string.rs` (or equivalent) and run `rustc --test -o build/ut_string tests/host_string.rs && ./build/ut_string`
- WP-M5.2-2 (no libc fallback): `rg -n "\\b(strlen|strcmp)\\b" -S src | rg -v "extern\\s+\"C\""`

### Feature M5.3: Minimal memory helpers (`memcpy`, `memset`)
Implementation tasks:
- Implement `memcpy`/`memset` (not explicitly demanded, but very useful immediately).

Acceptance criteria:
- Used by screen clear/scroll logic later (or verified by simple calls).

Implementation scope:
- `RUST` (pure helper functions; unit-testable on host)

Proof / tests (definition of done):
- UT-M5.3-1 (host unit tests): create `tests/host_mem.rs` and run `rustc --test -o build/ut_mem tests/host_mem.rs && ./build/ut_mem`
- WP-M5.3-2 (used from screen code once implemented): `rg -n "\\b(memcpy|memset)\\b" -S src | rg -v "tests?/|host"`

### Definition of Done (M5)
- `types + strlen/strcmp (+ memcpy/memset)` exist in a "kernel library" location and
  are used by kernel code.
- No host libc functions are used for these basics.

---

## Base Epic M6: Screen I/O Interface + Mandatory Output

### Feature M6.1: VGA text mode writer (VGA memory at `0xB8000`)
Implementation tasks:
- Implement a screen module with `putc` and `puts`.

Acceptance criteria:
- The kernel prints visible characters reliably.

Implementation scope:
- `RUST` (VGA writer) (+ `ASM` only for early boot)

Proof / tests (definition of done):
- MANUAL-M6.1-1 (runtime): boot and visually confirm multiple characters are printed correctly via the Rust screen module. (Automation: prefer AUTO-M6.1-1)
- UT-M6.1-1 (optional host test via buffer model): implement a buffer-backed VGA writer and test it with `rustc --test ...` (no hardware access)
- AUTO-M6.1-1 (preferred for CI): assert the VGA buffer headlessly via **Infra I2.1** (read guest memory at `0xB8000`); if you don’t need VGA-accurate CI, assert serial markers via **Infra I1.1** instead

### Feature M6.2: Newline handling (basic cursor movement)
Implementation tasks:
- Track row/col and implement `\n`.

Acceptance criteria:
- Multi-line output is readable and doesn't overwrite random positions.

Implementation scope:
- `RUST` (cursor state + newline logic; unit-testable with a buffer model)

Proof / tests (definition of done):
- UT-M6.2-1 (cursor math unit tests): create `tests/host_cursor.rs` and run `rustc --test -o build/ut_cursor tests/host_cursor.rs && ./build/ut_cursor`
- MANUAL-M6.2-1 (runtime): boot and print two lines; confirm line 2 appears on the next row. (Automation: prefer AUTO-M6.2-1)
- AUTO-M6.2-1 (preferred): the newline/cursor behavior should be locked by UT-M6.2-1; use **Infra I2.1** only if you want an end-to-end VGA assertion in CI

### Feature M6.3: Mandatory output: display `42`
Implementation tasks:
- Print `42` using your screen interface from `kmain` (preferred).

Acceptance criteria:
- On every boot, `42` is shown on screen.

Implementation scope:
- `RUST` (preferred) + `ASM` only as bootstrap

Proof / tests (definition of done):
- MANUAL-M6.3-1 (runtime): boot and confirm the first visible output includes `42`. (Automation: prefer AUTO-M6.3-1)
- WP-M6.3-2 (source proof): `rg -n "\"42\"|\\b42\\b" -S src`
- AUTO-M6.3-1 (preferred for CI): use **Infra I2.1** to assert `42` is present in the VGA text buffer at `0xB8000` (serial-only is not equivalent to “on screen”, but is acceptable as a smoke check via Infra I1.1)

### Definition of Done (M6)
- Screen I/O is an interface/module callable from the chosen language.
- `42` is printed and kernel halts cleanly afterward.

---

## Base Epic M7: Makefile (ASM + Language + Link + Image)

### Feature M7.1: Compile ASM sources with the correct target format
Implementation tasks:
- NASM uses a 32-bit output (`elf32`) for i386.

Acceptance criteria:
- ASM objects are linkable into an i386 kernel.

Implementation scope:
- `MAKE` + `ASM`

Proof / tests (definition of done):
- WP-M7.1-1 (nasm uses elf32): `make -n all arch=i386 | rg -n "\\bnasm\\b" | rg -q "(-f\\s*)?elf32"`
- WP-M7.1-2 (objects are ELF32 relocatable): `file build/arch/i386/*.o | rg -q "ELF 32-bit.*relocatable"`

### Feature M7.2: Compile chosen-language sources with freestanding flags
Implementation tasks:
- Add build rules for C/C++/Rust/etc. sources with the right flags.

Acceptance criteria:
- Build succeeds without linking to default host libraries.

Implementation scope:
- `MAKE` + `RUST`

Proof / tests (definition of done):
- WP-M7.2-1 (no-std configured): `rg -n "#!\\[no_std\\]" -S src`
- WP-M7.2-2 (no host libs on link line): `make -n all arch=i386 | rg -n "\\b(ld|rustc|gcc|clang)\\b" | rg -v "\\s-lc\\b"`
- WP-M7.2-3 (artifact has no dynamic loader): `KERNEL=build/kernel-i386.bin; ! readelf -lW "$KERNEL" | rg -n "INTERP"`

### Feature M7.3: Link all objects with custom linker script
Implementation tasks:
- Use `ld -T linker.ld` (and `-m elf_i386` for i386).

Acceptance criteria:
- The produced kernel boots via GRUB.

Implementation scope:
- `MAKE` + `LD`

Proof / tests (definition of done):
- WP-M7.3-1 (ld uses -m elf_i386 and your script): `make -n all arch=i386 | rg -n "\\bld\\b" | rg -q "(-m\\s+elf_i386).*\\s-T\\s+src/arch/i386/linker\\.ld"`
- MANUAL-M7.3-1 (boots): `make run arch=i386` and confirm GRUB loads the kernel and reaches your entry. (Automation: prefer AUTO-M7.3-1)
- AUTO-M7.3-1 (preferred for CI): use **Infra I0.1** as the boot gate; if it exits PASS, the link+GRUB load path succeeded

### Feature M7.4: Provide standard targets (`all`, `clean`, `iso`, `run`)
Acceptance criteria:
- From a clean tree, `make run` builds everything needed and boots.

Implementation scope:
- `MAKE` (+ `AUTOMATION`)

Proof / tests (definition of done):
- WP-M7.4-1 (targets exist): `make -qp | rg -n "^(all:|clean:|iso:|run:)" -n`
- MANUAL-M7.4-1 (clean build works): `make clean && make run arch=i386`. (Automation: prefer AUTO-M7.4-1)
- AUTO-M7.4-1 (preferred for CI): `make clean && make iso arch=i386 && make test-qemu arch=i386` (Infra I0.1) so the test terminates deterministically

### Definition of Done (M7)
- Makefile is the single source of truth for build/link/image/run.
- It builds ASM + chosen language, links with custom `.ld`, and produces a bootable image.

---

## Base Epic M8: Turn-In Packaging (Defense-Ready)

### Feature M8.1: Turn-in artifact checklist is satisfied
Deliverables required by the PDF:
- Code
- Makefile
- Basic virtual image for the kernel

Acceptance criteria:
- Peer can clone and boot using only the repo contents.

Implementation scope:
- `DOC` + `MAKE` (+ optional `AUTOMATION`)

Proof / tests (definition of done):
- WP-M8.1-1 (fresh clone build): `make clean && make iso arch=i386` succeeds on a machine with required tooling installed
- MANUAL-M8.1-1 (peer boot): on another machine: clone → `make run arch=i386` → observe boot. (Automation: see AUTO-M8.1-1 notes; cannot fully replace)
- AUTO-M8.1-1 (cannot replace): CI can run `make test-qemu arch=i386` (Infra I0.1), but the “peer boot on another machine” is still a defense requirement-style manual proof

### Feature M8.2: Enforce the 10 MB upper bound
Implementation tasks:
- Keep the turned-in image <= 10 MB.

Acceptance criteria:
- `ls -lh` shows the image file is <= 10 MB.

Implementation scope:
- `MAKE` (+ optional `AUTOMATION`)

Proof / tests (definition of done):
- WP-M8.2-1 (hard size check): `ISO=build/os-i386.iso; test $(wc -c < "$ISO") -le 10485760`

### Feature M8.3: Minimal "how to run" notes (optional but helpful)
Implementation tasks:
- Provide a 3-line quickstart in a README if the repo doesn’t have one.

Acceptance criteria:
- Another student can run `make run` without guessing.

Implementation scope:
- `DOC`

Proof / tests (definition of done):
- WP-M8.3-1 (README exists): `test -f README.md`
- WP-M8.3-2 (contains commands): `rg -n "make (doctor|verify|run|iso)" README.md`

### Definition of Done (M8)
- Repository contains exactly what the PDF asks for, and nothing essential is missing.
- Boot demonstration is reproducible in defense conditions.

---

# Bonus (Deferred) Epics

These are captured for completeness but intentionally not implemented right now.

## Bonus Epic B1: Scroll + Cursor Support

### Feature B1.1: Maintain cursor state
Implementation tasks:
- Track cursor row/col in the screen module.
- Clamp cursor to the screen bounds.

Acceptance criteria:
- Printing advances the cursor predictably (no overwriting random positions).

Implementation scope:
- `RUST` (screen module; buffer model recommended)

Proof / tests (definition of done):
- UT-B1.1-1 (cursor unit tests): create `tests/host_cursor_state.rs` and run `rustc --test -o build/ut_cursor_state tests/host_cursor_state.rs && ./build/ut_cursor_state`
- MANUAL-B1.1-1 (runtime): boot and print characters across line boundaries; observe cursor behavior is stable. (Automation: prefer AUTO-B1.1-1)
- AUTO-B1.1-1 (preferred): rely on UT-B1.1-1 for cursor correctness; optionally add an end-to-end VGA assertion with **Infra I2.1** if you want CI coverage

### Feature B1.2: Implement scrolling at bottom-of-screen
Implementation tasks:
- When cursor reaches the last row, scroll the screen buffer up by 1 line.
- Clear the last line after scrolling.

Acceptance criteria:
- Printing > 25 lines keeps the newest output visible.

Implementation scope:
- `RUST` (buffer operations; unit-testable on host)

Proof / tests (definition of done):
- UT-B1.2-1 (scroll unit tests): create `tests/host_scroll.rs` and run `rustc --test -o build/ut_scroll tests/host_scroll.rs && ./build/ut_scroll`
- MANUAL-B1.2-1 (runtime): boot and print 30+ lines; confirm older lines scroll off and new lines remain readable. (Automation: prefer AUTO-B1.2-1)
- AUTO-B1.2-1 (preferred): rely on UT-B1.2-1 for scrolling logic; optionally add an end-to-end VGA assertion with **Infra I2.1** to prove the visible buffer matches expectations

### Feature B1.3: Optional hardware cursor programming (VGA ports `0x3D4/0x3D5`)
Implementation tasks:
- Implement port I/O and program VGA cursor position registers.

Acceptance criteria:
- The hardware cursor position matches the software cursor.

Implementation scope:
- `RUST` + low-level port I/O (can be `ASM` or inline asm as needed)

Proof / tests (definition of done):
- MANUAL-B1.3-1 (runtime): boot and confirm a visible hardware cursor moves as text prints. (Automation: see AUTO-B1.3-1 notes; still mostly visual)
- AUTO-B1.3-1 (optional): hardware-cursor visibility is inherently visual; you can still use **Infra I1.1** serial markers to prove the code path executed, but keep MANUAL for the actual cursor proof

Definition of Done (B1):
- Printing > 25 lines keeps output readable and cursor behavior is predictable.

---

## Bonus Epic B2: Color Support

### Feature B2.1: VGA attribute/color model
Implementation tasks:
- Define VGA color constants and attribute encoding (foreground/background bits).
- Store the active attribute in the screen writer state.

Acceptance criteria:
- Printing in at least two distinct colors works reliably.

Implementation scope:
- `RUST` (screen module)

Proof / tests (definition of done):
- UT-B2.1-1 (attribute encoding tests): create `tests/host_color.rs` and run `rustc --test -o build/ut_color tests/host_color.rs && ./build/ut_color`
- MANUAL-B2.1-1 (runtime): boot and print two words in different colors. (Automation: prefer AUTO-B2.1-1)
- AUTO-B2.1-1 (preferred): UT-B2.1-1 proves encoding; to prove “on screen” without GUI, use **Infra I2.1** and assert the VGA attribute bytes in memory

### Feature B2.2: Screen API to set color per-print or per-screen
Implementation tasks:
- Add `set_color(fg, bg)` and/or scoped color APIs.

Acceptance criteria:
- A caller can change color without touching VGA memory directly.

Implementation scope:
- `RUST`

Proof / tests (definition of done):
- UT-B2.2-1 (API tests): host tests validate the writer uses the configured attribute
- MANUAL-B2.2-1 (runtime): boot and print lines with alternating colors via the API. (Automation: prefer AUTO-B2.2-1)
- AUTO-B2.2-1 (preferred): keep this automated via UT-B2.2-1; use **Infra I2.1** only if you want end-to-end VGA verification

Definition of Done (B2):
- Kernel prints at least two different colors reliably.

---

## Bonus Epic B3: printf/printk Helpers

### Feature B3.1: Minimal format engine (`%s %c %d %u %x %%`)
Implementation tasks:
- Implement a minimal formatter without dynamic allocation (no heap required).
- Support only the formats listed (no floats).

Acceptance criteria:
- Formatting works for representative inputs (including negatives for `%d`).

Implementation scope:
- `RUST` (pure formatting code; unit-testable on host)

Proof / tests (definition of done):
- UT-B3.1-1 (formatter unit tests): create `tests/host_format.rs` and run `rustc --test -o build/ut_format tests/host_format.rs && ./build/ut_format`
- WP-B3.1-2 (no allocation): `rg -n "\\b(Vec|String|Box|alloc::)\\b" -S src | rg -v "tests?/|host"`

### Feature B3.2: `printk` wrapper that prints to screen
Implementation tasks:
- Implement a `printk` (or similar) wrapper that uses the formatter and writes to the screen module.

Acceptance criteria:
- Kernel prints formatted debug information during boot.

Implementation scope:
- `RUST` (screen + formatting integration)

Proof / tests (definition of done):
- MANUAL-B3.2-1 (runtime): boot and confirm formatted output prints correctly (hex/decimal/string). (Automation: prefer AUTO-B3.2-1)
- AUTO-B3.2-1 (preferred for CI): assert formatted output via serial (Infra I1.1) and exit PASS (Infra I0.1); VGA-accurate assertion is possible via **Infra I2.1**

Definition of Done (B3):
- Kernel prints formatted debug information without dynamic allocation.

---

## Bonus Epic B4: Keyboard Input + Echo

### Feature B4.1: Read scancodes (polled or IRQ-driven)
Implementation tasks:
- Read scancodes from the PS/2 controller data port (`0x60`).
- Choose polling (simpler) or IRQ-driven (more correct).

Acceptance criteria:
- Scancodes are captured reliably for key presses.

Implementation scope:
- `RUST` + low-level port I/O

Proof / tests (definition of done):
- MANUAL-B4.1-1 (runtime): boot in QEMU, press keys, and confirm scancode handling path is exercised (e.g., debug print of scancodes). (Automation: see AUTO-B4.1-1 notes; optional)
- AUTO-B4.1-1 (optional): automation is possible but more work (QEMU monitor/QMP `sendkey` + serial assertions via Infra I1.1); keep MANUAL as the baseline proof

### Feature B4.2: Translate scancodes to ASCII (minimal map)
Implementation tasks:
- Implement a minimal scancode→ASCII map for alphanumerics.
- Handle at least backspace and newline.

Acceptance criteria:
- Common keys translate to expected ASCII.

Implementation scope:
- `RUST` (pure mapping logic; unit-testable on host)

Proof / tests (definition of done):
- UT-B4.2-1 (mapping unit tests): create `tests/host_scancode.rs` and run `rustc --test -o build/ut_scancode tests/host_scancode.rs && ./build/ut_scancode`

### Feature B4.3: Echo typed characters to screen
Implementation tasks:
- Integrate keyboard input with the screen writer.
- Implement backspace behavior (erase previous character on screen).

Acceptance criteria:
- Typed characters appear on screen and backspace behaves correctly.

Implementation scope:
- `RUST` (keyboard + screen integration)

Proof / tests (definition of done):
- MANUAL-B4.3-1 (runtime): boot and type; confirm echo + backspace on screen. (Automation: see AUTO-B4.3-1 notes; optional)
- AUTO-B4.3-1 (optional): use QMP `sendkey` to inject keystrokes and assert echo on serial (Infra I1.1) or VGA memory (Infra I2.1); keep MANUAL as baseline

Definition of Done (B4):
- Key presses appear on screen (at least for alphanumerics and backspace).

---

## Bonus Epic B5: Multiple Screens + Shortcuts

### Feature B5.1: N virtual terminal buffers
Implementation tasks:
- Maintain N screen buffers (e.g., N×80×25) and a cursor per terminal.

Acceptance criteria:
- Output for each terminal is preserved independently.

Implementation scope:
- `RUST` (buffer/state management; unit-testable on host)

Proof / tests (definition of done):
- UT-B5.1-1 (buffer isolation tests): create `tests/host_vt.rs` and run `rustc --test -o build/ut_vt tests/host_vt.rs && ./build/ut_vt`

### Feature B5.2: Shortcuts to switch active terminal
Implementation tasks:
- Detect a shortcut combo (e.g., Alt+Fn) and switch the active terminal.

Acceptance criteria:
- Switching changes the visible screen to the selected terminal.

Implementation scope:
- `RUST` (keyboard + terminal manager)

Proof / tests (definition of done):
- MANUAL-B5.2-1 (runtime): boot and use shortcuts to switch; confirm the visible buffer changes. (Automation: see AUTO-B5.2-1 notes; optional)
- AUTO-B5.2-1 (optional): same approach as keyboard automation—QMP `sendkey` + assert active-terminal markers on serial (Infra I1.1); keep MANUAL as baseline

### Feature B5.3: Persist output per terminal across switches
Implementation tasks:
- On switch, flush the target terminal buffer to VGA memory.
- Preserve inactive buffers while printing to the active one.

Acceptance criteria:
- Switching back restores previous output correctly.

Implementation scope:
- `RUST` (terminal manager + screen flush)

Proof / tests (definition of done):
- UT-B5.3-1 (restore tests): host tests validate switching preserves per-terminal content
- MANUAL-B5.3-1 (runtime): print on terminal 1, switch, print on terminal 2, switch back; confirm terminal 1 content is intact. (Automation: prefer AUTO-B5.3-1)
- AUTO-B5.3-1 (preferred): UT-B5.3-1 should lock the state logic; optionally add VGA memory end-to-end assertions via **Infra I2.1** if you want CI coverage

Definition of Done (B5):
- Switching terminals is reliable and does not corrupt screen state.
