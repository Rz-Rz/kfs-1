# KFS_1 - Epics and Features (Base vs Bonus)

Source: `docs/subject.pdf` (KFS_1: "Grub, boot and screen", Version 1).

This document is a requirements-to-backlog translation split into:
- **Base (Mandatory)**: what you must deliver
- **Bonus (Deferred)**: explicitly *not* doing now, but captured for later

Each epic has:
- Multiple features
- Acceptance criteria and validation hints
- A per-epic **Definition of Done (DoD)**

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

This repo already builds a GRUB ISO and contains a Multiboot2 header, but a few items
are currently out of alignment with KFS_1 requirements:
- i386 mandate vs current naming:
  - Subject mandates i386 (32-bit).
  - Repo uses `src/arch/x86_64`, but `boot.asm` is `bits 32` and the Multiboot2 header
    uses architecture 0 (protected mode i386).
- Toolchain mismatch (must be fixed for a clean, defensible base solution):
  - `.asm-lsp.toml` expects `elf32`.
  - `Makefile` uses `nasm -felf64` and `qemu-system-x86_64`.
- Mandatory output mismatch:
  - `boot.asm` prints `OK`, but KFS_1 requires printing `42`.

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
- Ensure assembler output is 32-bit (`nasm -f elf32`).
- Ensure linker mode is 32-bit (`ld -m elf_i386`).
- Ensure QEMU run target matches (`qemu-system-i386`).

Acceptance criteria:
- `file build/kernel-*.bin` indicates a 32-bit kernel artifact.
- Boot works under `qemu-system-i386`.

### Feature M0.2: Enforce "no host libs" and "freestanding" compilation rules
Implementation tasks (adapt to chosen language):
- Compile freestanding and disable default libs/startup objects.
- Avoid exceptions/RTTI/new/delete until you have a kernel allocator/runtime.

Acceptance criteria:
- Kernel artifact is not dynamically linked (no `.interp`, no `.dynamic`).
- No unresolved external symbols from libc at link time.

### Feature M0.3: Size discipline baked into the workflow
Implementation tasks:
- Prefer stripped/minimal artifacts for the image.
- Avoid committing large generated files besides the required "virtual image".

Acceptance criteria:
- Produced virtual image is <= 10 MB.

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

### Feature M1.2: "Install GRUB on a virtual image" (alternate path: tiny disk image)
This is optional if your evaluation accepts an ISO, but it exactly matches the wording
in the subject and can reduce ambiguity during defense.

Implementation tasks (one possible approach):
- Create a small raw image file.
- Partition/format it minimally.
- Install GRUB to it and place kernel + `grub.cfg`.

Acceptance criteria:
- The disk image boots via QEMU and reaches the kernel.
- Image is <= 10 MB.

### Feature M1.3: GRUB config uses a consistent Multiboot version
Implementation tasks:
- Pick Multiboot v1 or v2 and keep it consistent:
  - Multiboot2: `multiboot2 /boot/kernel.bin` and MB2 header magic `0xe85250d6`.

Acceptance criteria:
- GRUB does not print Multiboot magic/header errors during boot.

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

### Feature M2.2: ASM entry point sets up a safe execution environment
Implementation tasks:
- Define the entry symbol that GRUB jumps to (e.g., `start`).
- Initialize a stack.
- Optionally clear direction flag (`cld`) and ensure interrupts are in a known state.

Acceptance criteria:
- Kernel doesn't crash due to missing stack or undefined state.

### Feature M2.3: Transfer control to a higher-level `kmain`/`main`
Implementation tasks:
- Provide a callable function in the chosen language (`kmain` recommended).
- Ensure calling convention matches i386 cdecl-like assumptions.
- If `kmain` returns, halt cleanly (`cli; hlt; jmp $`).

Acceptance criteria:
- You can prove control flow reached `kmain` (e.g., print from `kmain`).

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

### Feature M3.2: Provide standard sections for growth
Implementation tasks:
- Define `.text`, `.rodata`, `.data`, `.bss`.
- Ensure `.bss` is allocated properly (and can be zeroed later if needed).

Acceptance criteria:
- Adding a C/Rust module does not require reworking the whole linker layout.

### Feature M3.3: Export useful layout symbols
Implementation tasks:
- Export symbols like `kernel_start`, `kernel_end`, `bss_start`, `bss_end` (names flexible).

Acceptance criteria:
- Other kernel code can reference those symbols without hardcoding addresses.

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

### Feature M4.2: Minimal "kernel init" sequence (even if tiny)
Implementation tasks:
- Establish a minimal init pattern (e.g., `kmain` calls `vga_init`, then prints).
- Keep it structured for later KFS modules.

Acceptance criteria:
- Boot-to-output flow is in the chosen language, not only ASM.

### Feature M4.3: Clean halt behavior
Implementation tasks:
- Provide a consistent halt function (e.g., `cpu_halt_forever()`).

Acceptance criteria:
- After printing, kernel halts without rebooting or triple faulting.

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

### Feature M5.2: Minimal string helpers (`strlen`, `strcmp`)
Implementation tasks:
- Implement `strlen` and `strcmp` (explicitly mentioned by the subject).

Acceptance criteria:
- Helpers behave correctly for typical strings used by your screen interface.

### Feature M5.3: Minimal memory helpers (`memcpy`, `memset`)
Implementation tasks:
- Implement `memcpy`/`memset` (not explicitly demanded, but very useful immediately).

Acceptance criteria:
- Used by screen clear/scroll logic later (or verified by simple calls).

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

### Feature M6.2: Newline handling (basic cursor movement)
Implementation tasks:
- Track row/col and implement `\n`.

Acceptance criteria:
- Multi-line output is readable and doesn't overwrite random positions.

### Feature M6.3: Mandatory output: display `42`
Implementation tasks:
- Print `42` using your screen interface from `kmain` (preferred).

Acceptance criteria:
- On every boot, `42` is shown on screen.

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

### Feature M7.2: Compile chosen-language sources with freestanding flags
Implementation tasks:
- Add build rules for C/C++/Rust/etc. sources with the right flags.

Acceptance criteria:
- Build succeeds without linking to default host libraries.

### Feature M7.3: Link all objects with custom linker script
Implementation tasks:
- Use `ld -T linker.ld` (and `-m elf_i386` for i386).

Acceptance criteria:
- The produced kernel boots via GRUB.

### Feature M7.4: Provide standard targets (`all`, `clean`, `iso`, `run`)
Acceptance criteria:
- From a clean tree, `make run` builds everything needed and boots.

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

### Feature M8.2: Enforce the 10 MB upper bound
Implementation tasks:
- Keep the turned-in image <= 10 MB.

Acceptance criteria:
- `ls -lh` shows the image file is <= 10 MB.

### Feature M8.3: Minimal "how to run" notes (optional but helpful)
Implementation tasks:
- Provide a 3-line quickstart in a README if the repo doesn’t have one.

Acceptance criteria:
- Another student can run `make run` without guessing.

### Definition of Done (M8)
- Repository contains exactly what the PDF asks for, and nothing essential is missing.
- Boot demonstration is reproducible in defense conditions.

---

# Bonus (Deferred) Epics

These are captured for completeness but intentionally not implemented right now.

## Bonus Epic B1: Scroll + Cursor Support

### Feature B1.1: Maintain cursor state
### Feature B1.2: Implement scrolling at bottom-of-screen
### Feature B1.3: Optional hardware cursor programming (VGA ports `0x3D4/0x3D5`)

Definition of Done (B1):
- Printing > 25 lines keeps output readable and cursor behavior is predictable.

---

## Bonus Epic B2: Color Support

### Feature B2.1: VGA attribute/color model
### Feature B2.2: Screen API to set color per-print or per-screen

Definition of Done (B2):
- Kernel prints at least two different colors reliably.

---

## Bonus Epic B3: printf/printk Helpers

### Feature B3.1: Minimal format engine (`%s %c %d %u %x %%`)
### Feature B3.2: `printk` wrapper that prints to screen

Definition of Done (B3):
- Kernel prints formatted debug information without dynamic allocation.

---

## Bonus Epic B4: Keyboard Input + Echo

### Feature B4.1: Read scancodes (polled or IRQ-driven)
### Feature B4.2: Translate scancodes to ASCII (minimal map)
### Feature B4.3: Echo typed characters to screen

Definition of Done (B4):
- Key presses appear on screen (at least for alphanumerics and backspace).

---

## Bonus Epic B5: Multiple Screens + Shortcuts

### Feature B5.1: N virtual terminal buffers
### Feature B5.2: Shortcuts to switch active terminal
### Feature B5.3: Persist output per terminal across switches

Definition of Done (B5):
- Switching terminals is reliable and does not corrupt screen state.
