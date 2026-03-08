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

## Infra Epic I4: Linker / ELF Hygiene Gates

Goal:
- Catch subtle linker-layout regressions before they become boot failures or silent ELF baggage.

Motivation:
- The M3.2 section proofs establish the core layout, but future toolchain changes can still
  introduce unexpected sections, orphan inputs, or hidden runtime metadata.
- These checks are hardening gates for CI, not subject-mandated deliverables.

### Feature I4.1: Emit and inspect a linker map file
Implementation tasks:
- Ask `ld` to emit a map file for the final kernel link (for example `-Map build/kernel-i386.map`).
- Preserve the map artifact in `build/` for local inspection and CI debugging.
- Add at least one host-side assertion that inspects the map and proves key input sections
  land in the expected output sections.

Acceptance criteria:
- Every kernel link produces a readable map file.
- The project can prove exact input-to-output section routing from the linker’s own report.

Implementation scope:
- `MAKE` + `LD` + `AUTOMATION`

Proof / tests (definition of done):
- WP-I4.1-1 (link command emits a map file): `make -n all arch=i386 | rg -n -- "-Map\\s+build/kernel-i386\\.map"`
- WP-I4.1-2 (artifact exists after build): `make all arch=i386 && test -f build/kernel-i386.map`
- WP-I4.1-3 (map proves a subsection routing example): `rg -n "KFS_RODATA_SUBSECTION_MARKER|\\.rodata\\.kfs_test|\\.rodata" build/kernel-i386.map`

### Feature I4.2: Fail the link on orphan sections
Implementation tasks:
- If supported by the project `ld`, add `--orphan-handling=error` to the final kernel link.
- Document the expected failure mode when a new input section appears without an explicit rule.
- Add a regression proof that the link command includes the orphan-handling gate.

Acceptance criteria:
- A newly introduced unmapped input section fails the link immediately instead of silently
  landing wherever the linker decides.

Implementation scope:
- `MAKE` + `LD`

Proof / tests (definition of done):
- WP-I4.2-1 (link command enables orphan rejection): `make -n all arch=i386 | rg -n -- "--orphan-handling=error"`
- WP-I4.2-2 (negative proof): inject a temporary unmapped input section and confirm the link fails with an orphan-section error

### Feature I4.3: Denylist suspicious ELF baggage sections explicitly
Implementation tasks:
- Add a host-side ELF inspection test that fails if the final kernel contains suspicious
  sections such as:
  - `.eh_frame`
  - `.gcc_except_table`
  - `.init_array`
  - `.fini_array`
  - `.got`, `.got.plt`
  - `.plt`
  - `.dynamic`, `.interp`
  - `.rela.*`, `.rel.*`
  - `.note.gnu.build-id`
- Keep this denylist separate from the broader allocatable-section allowlist so the failure
  message names the exact unexpected baggage.

Acceptance criteria:
- The kernel ELF is free of common hosted-runtime / unwinding / dynamic-link sections that do
  not belong in a tiny freestanding kernel.

Implementation scope:
- `AUTOMATION` (+ final kernel artifact)

Proof / tests (definition of done):
- WP-I4.3-1 (denylist check): `KERNEL=build/kernel-i386.bin; ! readelf -SW "$KERNEL" | rg -n "\\.(eh_frame|gcc_except_table|init_array|fini_array|got|got\\.plt|plt|dynamic|interp|note\\.gnu\\.build-id)\\b|\\.rel\\.|\\.rela\\."`
- WP-I4.3-2 (daily gate): `make test` includes a visible ELF-baggage denylist step

Definition of Done (I4):
- The build either rejects or clearly reports unexpected linker/ELF baggage before it can
  silently ship in the kernel image.

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
- "Write helpers like kernel types or basic functions (strlen, strcmp, ...)" -> Base Epic M5 (repo decision: use Rust native types directly)
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
- The hard gate is `make test arch=i386`, which runs `scripts/boot-tests/freestanding-kernel.sh` on the freshly built
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

Stability / adversarial proofs (recommended in visible CI output):
- AT-M0.2-1 (the gate is enforced on an ASM + Rust linked kernel, not ASM-only): `nm -n build/kernel-i386-test.bin | rg -n "\\bkfs_rust_marker\\b"`
  Why it matters: an ASM-only kernel can accidentally look freestanding while the chosen-language
  path is missing or not linked at all.
- AT-M0.2-2 (release artifact can also be checked, not only the fast test artifact): `KFS_M0_2_INCLUDE_RELEASE=1 bash scripts/boot-tests/freestanding-kernel.sh i386 all`
  Why it matters: the daily gate runs on the fresh test kernel, but the release kernel should stay
  clean as well.
- AT-M0.2-3 (marker-string checks are defense-in-depth, separate from ELF metadata checks): `bash scripts/boot-tests/freestanding-kernel.sh i386 no-libc-strings`, `bash scripts/boot-tests/freestanding-kernel.sh i386 no-loader-strings`
  Why it matters: `.interp` / `.dynamic` are the primary proofs. The string checks are additional
  alarms for hosted-runtime leakage that might otherwise be easy to overlook.

Negative / rejection proofs (real bad-hosted-kernel cases, not mocks):
- RT-M0.2-1 (rejects forced `.interp` / `PT_INTERP` metadata): `bash scripts/rejection-tests/freestanding-rejections.sh i386 interp-pt-interp-present`
- RT-M0.2-2 (rejects forced `.dynamic` metadata): `bash scripts/rejection-tests/freestanding-rejections.sh i386 dynamic-section-present`
- RT-M0.2-3 (rejects an unresolved external symbol): `bash scripts/rejection-tests/freestanding-rejections.sh i386 unresolved-external-symbol`
- RT-M0.2-4 (rejects libc / dynamic-loader marker strings): `bash scripts/rejection-tests/freestanding-rejections.sh i386 host-runtime-marker-strings`
  Why they matter: these tests deliberately contaminate an otherwise real kernel build and prove
  the no-host-libs gate fails for the exact hosted-runtime smells it claims to detect.

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
  - In this repo: `make img-test arch=i386 && bash scripts/boot-tests/qemu-boot.sh i386 drive` (PASS via isa-debug-exit)

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
Intent:
- Provide the project-owned linker script required by the subject instead of relying on a
  host default `.ld` file.
- Keep this feature focused on the **existence and baseline structure** of the linker
  script itself.
- Do **not** use this feature to prove the whole kernel link command or boot path; those
  belong to M7.3 and boot features.

Implementation tasks:
- Create `src/arch/i386/linker.ld`.
- Define `ENTRY(start)` (or the chosen kernel entry symbol).
- Set the kernel load address to 1 MiB (`. = 1M;`).
- Place the Multiboot header early in the image through the linker layout.

Acceptance criteria:
- The repo contains its own linker script for the kernel.
- The script defines the entry point and base load address needed by the kernel layout.
- The script places the Multiboot header before the main code region.

Implementation scope:
- `LD`

Proof / tests (definition of done):
- WP-M3.1-1 (linker script exists + has required directives): `rg -n "^(ENTRY\\(|SECTIONS\\s*\\{|\\s*\\.\\s*=\\s*1M;)" -S src/arch/i386/linker.ld`
- WP-M3.1-2 (Multiboot header is explicitly placed early by the linker script): `rg -n "\\*\\(\\.multiboot_header\\)" -S src/arch/i386/linker.ld`

### Feature M3.2: Standard data sections are explicitly mapped in the custom linker script
Intent:
- Extend the custom kernel linker script so the final kernel ELF explicitly supports the
  standard non-code sections emitted by ASM/Rust objects: `.rodata`, `.data`, and `.bss`.
- Keep this feature focused on **section layout/materialization** inside our own
  `linker.ld`.
- Do **not** use this feature to prove that the repo uses a custom linker script at all,
  or that the kernel boots; those concerns belong to M3.1 and M7.3.

Implementation tasks:
- Define output sections for `.rodata`, `.data`, and `.bss` in `src/arch/i386/linker.ld`.
- Collect matching input sections, including wildcard variants:
  - `.rodata`, `.rodata.*`
  - `.data`, `.data.*`
  - `.bss`, `.bss.*`
- Include `COMMON` storage in `.bss`.
- Add linked marker symbols so the final ELF can prove:
  - read-only data lands in `.rodata`
  - initialized writable data lands in `.data`
  - zero-initialized writable data lands in `.bss`

Acceptance criteria:
- The custom linker script explicitly defines `.rodata`, `.data`, and `.bss`.
- The final kernel ELF contains `.text`, `.rodata`, `.data`, and `.bss`.
- A linked read-only symbol is placed in `.rodata`.
- A linked initialized writable symbol is placed in `.data`.
- A linked zero-initialized writable symbol is placed in `.bss`.
- `.bss` is emitted as `NOBITS` in the final ELF.

Implementation scope:
- `LD` (+ `RUST`)

Proof / tests (definition of done):
- WP-M3.2-1 (linker script defines the required sections): `rg -n "^\\s*\\.(rodata|data|bss)\\b" -S src/arch/i386/linker.ld`
- WP-M3.2-2 (artifact contains the expected sections): `KERNEL=build/kernel-i386.bin; readelf -SW "$KERNEL" | rg -n "\\.(text|rodata|data|bss)\\b"`
- WP-M3.2-3 (linked read-only marker lands in `.rodata`): `nm -n build/kernel-i386.bin | rg -n "[[:space:]]R[[:space:]]+KFS_RODATA_MARKER$"`
- WP-M3.2-4 (linked initialized writable marker lands in `.data`): `nm -n build/kernel-i386.bin | rg -n "[[:space:]]D[[:space:]]+KFS_DATA_MARKER$"`
- WP-M3.2-5 (linked zero-initialized marker lands in `.bss`): `nm -n build/kernel-i386.bin | rg -n "[[:space:]][Bb][[:space:]]+KFS_BSS_MARKER$"`
- WP-M3.2-6 (`.bss` is emitted as zero-init allocated storage): `readelf -SW build/kernel-i386.bin | rg -n "\\.bss\\b.*NOBITS"`
- WP-M3.2-7 (build gate runs immediately after link): `make -n all arch=i386 | rg -n "m3\\.2-kernel-sections\\.sh"`

Stability / adversarial proofs (recommended in visible CI output):
- AT-M3.2-1 (wildcard capture exists for future subsection names): `bash scripts/stability-tests/section-stability.sh i386 rodata-wildcard-capture`, `bash scripts/stability-tests/section-stability.sh i386 data-wildcard-capture`, `bash scripts/stability-tests/section-stability.sh i386 bss-wildcard-capture`, `bash scripts/stability-tests/section-stability.sh i386 common-wildcard-capture`
  Why it matters: future compiler output often uses names like `.rodata.foo`, `.data.bar`,
  or `.bss.baz`, not just the bare base names. This proves the linker script keeps wildcard
  rules and `COMMON` support so later growth does not silently create orphan sections.
- AT-M3.2-2 (read-only subsection canary still folds into output `.rodata`): `bash scripts/stability-tests/section-stability.sh i386 rodata-subsection-marker`
  Why it matters: proves `*(.rodata .rodata.*)` is doing real work, not just the base
  `.rodata` case.
- AT-M3.2-3 (initialized writable subsection canary still folds into output `.data`): `bash scripts/stability-tests/section-stability.sh i386 data-subsection-marker`
  Why it matters: proves `.data.*` inputs remain in initialized writable storage rather than
  becoming orphans.
- AT-M3.2-4 (zero-init subsection canary still folds into output `.bss`): `bash scripts/stability-tests/section-stability.sh i386 bss-subsection-marker`
  Why it matters: proves future `.bss.*` globals still end up in real BSS storage.
- AT-M3.2-5 (`COMMON` symbol is folded into `.bss`): `bash scripts/stability-tests/section-stability.sh i386 common-bss-marker`
  Why it matters: `COMMON` is an older but still real zero-init storage class; without
  `*(COMMON)`, some toolchains/ASM inputs will not land in `.bss`.
- AT-M3.2-6 (allocatable section allowlist holds): `bash scripts/stability-tests/section-stability.sh i386 alloc-section-allowlist`
  Why it matters: catches unexpected loadable sections such as `.eh_frame` before they sneak
  into the shipped kernel image.

Negative / rejection proofs (real bad-linker cases, not mocks):
- RT-M3.2-1 (rejects missing `.text`): `bash scripts/rejection-tests/section-rejections.sh i386 text-missing`
- RT-M3.2-2 (rejects wrong `.text` type): `bash scripts/rejection-tests/section-rejections.sh i386 text-wrong-type`
- RT-M3.2-3 (rejects missing `.rodata`): `bash scripts/rejection-tests/section-rejections.sh i386 rodata-missing`
- RT-M3.2-4 (rejects wrong `.rodata` type): `bash scripts/rejection-tests/section-rejections.sh i386 rodata-wrong-type`
- RT-M3.2-5 (rejects missing `.data`): `bash scripts/rejection-tests/section-rejections.sh i386 data-missing`
- RT-M3.2-6 (rejects wrong `.data` type): `bash scripts/rejection-tests/section-rejections.sh i386 data-wrong-type`
- RT-M3.2-7 (rejects missing `.bss`): `bash scripts/rejection-tests/section-rejections.sh i386 bss-missing`
- RT-M3.2-8 (rejects wrong `.bss` type): `bash scripts/rejection-tests/section-rejections.sh i386 bss-wrong-type`
  Why they matter: these tests compile the real kernel with intentionally broken linker scripts
  and prove the build gate rejects malformed ELF layouts immediately after `ld`, rather than only
  detecting them later in a standalone checker run.

### Feature M3.3: Export canonical kernel and BSS boundary symbols
Intent:
- Extend the custom linker script so the final kernel ELF exports stable boundary symbols for
  the whole kernel image and the `.bss` region: `kernel_start`, `kernel_end`, `bss_start`,
  and `bss_end`.
- Keep this feature focused on **publishing trustworthy layout metadata** from the final link.
- Do **not** use this feature to prove section materialization/layout itself (M3.2), actual
  runtime memory initialization (M4.2), or the build’s use of the linker script at all (M7.3).

Implementation tasks:
- Define `kernel_start` before the first emitted kernel section.
- Define `bss_start` at the beginning of output `.bss`.
- Define `bss_end` at the end of output `.bss`.
- Define `kernel_end` at the end of the linked kernel image.
- Add linker `ASSERT`s that reject impossible layouts:
  - `kernel_start <= bss_start`
  - `bss_start <= bss_end`
  - `bss_end <= kernel_end`
- Add a Rust-side consumer that references these symbols as addresses and derives kernel/BSS
  spans without hardcoded constants.

Acceptance criteria:
- The final kernel ELF exports `kernel_start`, `kernel_end`, `bss_start`, and `bss_end`.
- Rust code can reference those exact symbols and derive kernel/BSS ranges from their addresses.
- The linker rejects malformed symbol ordering at link time.
- This feature does not claim to prove `.bss` zeroing or general memory-safety behavior; it
  only proves the exported layout metadata is present and sane.

Implementation scope:
- `LD` (+ `RUST`)

Proof / tests (definition of done):
- WP-M3.3-1 (linker script defines the canonical boundary symbols): `rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b" -S src/arch/i386/linker.ld`
- WP-M3.3-2 (release artifact exports the boundary symbols): `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b"`
- WP-M3.3-3 (test artifact exports the boundary symbols): `KERNEL=build/kernel-i386-test.bin; nm -n "$KERNEL" | rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b"`
- WP-M3.3-4 (Rust layout consumer declares and references the symbols): `rg -n "kernel_start|kernel_end|bss_start|bss_end|addr_of!" -S src/rust/layout_symbols.rs`
- WP-M3.3-5 (repo proof script covers exported symbols): `bash scripts/boot-tests/layout-symbols.sh i386`

Stability / adversarial proofs (recommended in visible CI output):
- AT-M3.3-1 (linker assertions exist for boundary ordering): `rg -n "\\bASSERT\\b" -S src/arch/i386/linker.ld`
- AT-M3.3-2 (release artifact ordering is monotonic): `bash scripts/boot-tests/layout-symbols.sh i386 release-symbol-ordering`
- AT-M3.3-3 (test artifact ordering is monotonic): `bash scripts/boot-tests/layout-symbols.sh i386 test-symbol-ordering`
  Why they matter: exported symbols are only useful if they describe a sane range. These
  checks prevent a “symbols exist but are semantically wrong” false green.

Negative / rejection proofs (real bad-linker cases, not mocks):
- RT-M3.3-1 (rejects `bss_start` before `kernel_start`): `bash scripts/rejection-tests/layout-symbol-rejections.sh i386 bss-before-kernel`
- RT-M3.3-2 (rejects `bss_end` before `bss_start`): `bash scripts/rejection-tests/layout-symbol-rejections.sh i386 bss-end-before-bss-start`
- RT-M3.3-3 (rejects `kernel_end` before `bss_end`): `bash scripts/rejection-tests/layout-symbol-rejections.sh i386 kernel-end-before-bss-end`
  Why they matter: these tests prove the link fails on impossible layouts instead of silently
  shipping misleading boundary symbols.

### Definition of Done (M3)
- Linker script is self-contained, reviewed, and demonstrably used in the build.
- Section layout is stable enough to add more code without fragile hacks.

---

## Base Epic M4: Minimal Kernel in Your Chosen Language

### Feature M4.1: A real `kmain` entry point in the chosen language
Intent:
- Prove the real **release** boot path transfers control from the ASM entry point into a
  Rust-defined kernel entry function named `kmain`.
- Keep this feature focused on **entry-point identity and reachability** in the final linked
  kernel image.
- Do **not** use this feature to prove runtime memory assumptions (M4.2), the screen API (M6),
  or linker-symbol semantics beyond “the entry point is present and called” (M3.3).

Implementation tasks:
- Implement `#[no_mangle] pub extern "C" fn kmain() -> !` in Rust.
- Keep `kmain` freestanding: no allocator and no kernel-side assumptions that require an OS/runtime.
- Make the i386 ASM boot entry (`start`) set up the minimal execution environment and then
  transfer control directly to `kmain`.
- Keep the release proof focused on the **release kernel artifact**; test-only fast paths must
  not be allowed to masquerade as proof that Rust actually ran.

Acceptance criteria:
- The final release kernel exports an unmangled text symbol named `kmain`.
- The ASM boot entry calls `kmain` on the release path, not only in a test-only build.
- `kmain` is part of the final shipped kernel image and is not dead code or a detached helper.
- The proof distinguishes “symbol exists” from “boot path actually targets that symbol”.

Implementation scope:
- `RUST` (+ `ASM` call site)

Proof / tests (definition of done):
- WP-M4.1-1 (Rust defines the canonical entry signature): `rg -n "#\\[no_mangle\\]|extern\\s+\"C\"\\s+fn\\s+kmain\\s*\\(\\)\\s*->\\s*!" -S src/kernel src/rust`
- WP-M4.1-2 (release kernel exports `kmain` as text): `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "[[:space:]]T[[:space:]]+kmain$"`
- WP-M4.1-3 (release boot entry calls `kmain` from `start`): `objdump -d build/kernel-i386.bin | sed -n '/<start>:/,/^$/p' | rg -n "call[[:space:]]+.*<kmain>"`
- WP-M4.1-4 (repo proof scripts cover the release symbol + callsite): `bash scripts/boot-tests/release-kmain-symbol.sh i386 release-kernel-exports-kmain`, `bash scripts/boot-tests/release-kmain-callsite.sh i386 release-boot-calls-kmain`
- WP-M4.1-5 (runtime proof reaches Rust entry in QEMU): `bash scripts/boot-tests/runtime-markers.sh i386 runtime-reaches-kmain`

Stability / adversarial proofs (recommended in visible CI output):
- AT-M4.1-1 (release proof is anchored to the real `start` block): `objdump -d build/kernel-i386.bin | sed -n '/<start>:/,/^$/p'`
  Why it matters: a loose “somewhere in the ELF there is a call to kmain” check is weaker than a
  proof that the actual CPU entry block calls into Rust.
- AT-M4.1-2 (entry symbol remains unmangled across toolchain changes): `bash scripts/boot-tests/release-kmain-symbol.sh i386 release-kernel-exports-kmain`
  Why it matters: freestanding Rust can silently drift into a mangled or optimized-away entry if
  the ABI markers change.
- AT-M4.1-3 (test automation also executes Rust entry, not just static artifact checks): `bash scripts/boot-tests/runtime-markers.sh i386 runtime-reaches-kmain`
  Why it matters: this closes the old gap where a test harness could prove only “the image boots”
  without proving that `kmain` itself actually ran.

Negative / rejection proofs (real bad-entry cases, not mocks):
- RT-M4.1-1 (rejects missing/unmangled `kmain`): temporarily remove `#[no_mangle]` or rename the symbol and confirm `bash scripts/boot-tests/release-kmain-symbol.sh i386 release-kernel-exports-kmain` fails
- RT-M4.1-2 (rejects a release boot path that no longer calls Rust): temporarily remove `call kmain` from the release path in `src/arch/i386/boot.asm` and confirm `bash scripts/boot-tests/release-kmain-callsite.sh i386 release-boot-calls-kmain` fails
- MANUAL-M4.1-1 (observable behavior from Rust entry): boot the release ISO in QEMU and confirm the first visible output is produced by Rust `kmain` rather than by an ASM-only fallback. (Automation: prefer AUTO-M4.1-1)
- AUTO-M4.1-1 (current CI proof): `bash scripts/boot-tests/runtime-markers.sh i386 runtime-reaches-kmain`
  Why it matters: the workflow proofs above establish symbol identity and the static call edge. A
  runtime marker closes the gap and proves the CPU actually executed Rust code after boot.

### Feature M4.2: Minimal early kernel init validates runtime assumptions before normal work
Intent:
- Establish a minimal Rust-side init step after `kmain` that validates the runtime assumptions
  the kernel depends on before later features build on them.
- Keep this feature focused on **runtime use of already-exported layout metadata** and the
  boot path’s zero-initialized `.bss` guarantee.
- Do **not** use this feature to redefine linker symbols (M3.3) or to own the full screen I/O
  API (M6).
- This is a **runtime-assumption** feature: it must be proved by executing kernel code, not only
  by inspecting ELF metadata.

Implementation tasks:
- Add a dedicated Rust early-init step that runs immediately after entering `kmain`, before the
  “normal” kernel flow.
- Add a Rust `.bss` canary object that is expected to start at zero on first observation.
- In early init, read that `.bss` canary before any writes and treat non-zero as a hard failure.
- Read the exported `kernel_start`, `kernel_end`, `bss_start`, and `bss_end` bounds at runtime and
  derive spans without hardcoded addresses.
- Validate the basic ordering/range assumptions in Rust before continuing.
- Emit fixed success/failure markers so runtime assertions can be automated without depending on
  free-form text output.

Acceptance criteria:
- Boot reaches Rust early init after `kmain`.
- A `.bss` object is observed as zero at runtime before being written.
- Early init can read the exported kernel/BSS bounds at runtime without hardcoded addresses.
- Early init rejects impossible or suspicious layout ranges instead of silently continuing.
- Failure is externally observable if the runtime assumptions do not hold.
- Success is externally observable in an ordered way so tests can distinguish
  “Rust started” from “Rust validated runtime assumptions”.

Implementation scope:
- `RUST` (+ `ASM` call site already covered by M2.3 / M4.1)

Proof / tests (definition of done):
- WP-M4.2-1 (Rust defines a dedicated zero-init canary in BSS): `rg -n "\\bstatic\\s+mut\\b|\\bstatic\\b" -S src | rg -n "BSS|ZERO|CANARY"`
- WP-M4.2-2 (Rust early-init code references the exported layout bounds): `rg -n "kernel_start|kernel_end|bss_start|bss_end" -S src`
- WP-M4.2-3 (boot path reaches a dedicated early-init step before the normal output path): `rg -n "early_init|init" -S src/kernel src/rust`
- WP-M4.2-4 (runtime proves ordered success markers): `bash scripts/boot-tests/runtime-markers.sh i386 runtime-markers-are-ordered`

Stability / adversarial proofs (recommended in visible CI output):
- AT-M4.2-1 (ordered runtime markers are fixed tokens, not prose): runtime emits machine-checkable tokens such as `KMAIN_OK`, `BSS_OK`, `LAYOUT_OK`, and `EARLY_INIT_OK`
  Why it matters: free-form boot logs are brittle. Fixed tokens let tests prove exact sequencing.
- AT-M4.2-2 (layout checks consume exported symbols, not duplicated constants): `rg -n "kernel_start|kernel_end|bss_start|bss_end" -S src | rg -v "linker\\.ld"`
  Why it matters: this feature is supposed to prove the running kernel can trust M3.3’s exported
  layout metadata, not reintroduce hardcoded addresses in Rust.
- AT-M4.2-3 (the BSS canary is read before first write): keep the early-init code structured so a
  source or trace-based test can show “read/compare first, write later”
  Why it matters: otherwise the check could self-fulfill by zeroing the canary before observing it.

Negative / rejection proofs (real bad-runtime cases, not mocks):
- RT-M4.2-1 (rejects non-zero BSS canary): build a dedicated failing test variant that seeds the canary or bypasses zero-init and confirm runtime emits `BSS_FAIL` and exits FAIL via Infra I0.1
- RT-M4.2-2 (rejects malformed layout ordering at runtime): build a dedicated failing test variant with an impossible span/ordering assumption and confirm runtime emits `LAYOUT_FAIL` and exits FAIL
- RT-M4.2-3 (rejects continuing past early init after a failed assumption): ensure the failure path does not print the normal success marker or reach the normal screen flow
- RT-M4.2-4 (repo rejection scripts cover both failure classes): `bash scripts/rejection-tests/runtime-init-rejections.sh i386 dirty-bss-canary-fails`, `bash scripts/rejection-tests/runtime-init-rejections.sh i386 bad-layout-fails`
- MANUAL-M4.2-1 (runtime): boot and confirm early init reaches the normal output path only after the zero-init and layout checks succeed
- AUTO-M4.2-1 (current CI proof): `bash scripts/boot-tests/runtime-markers.sh i386 runtime-confirms-bss-zero`, `bash scripts/boot-tests/runtime-markers.sh i386 runtime-confirms-layout`, `bash scripts/boot-tests/runtime-markers.sh i386 runtime-completes-early-init`
  Why it matters: M3.3 proves the linker exported sane addresses. This feature proves the
  running kernel can actually depend on those addresses and on zero-init behavior before
  higher-level code starts using globals/statics.

### Feature M4.3: Clean halt behavior
Intent:
- Provide a single, predictable “stop the CPU here” behavior for the minimal kernel once boot
  work is done or when a fatal condition is reached.
- Keep this feature focused on **terminal CPU behavior** (`cli`/`hlt` loop or equivalent).
- Do **not** use this feature to hide missing runtime-exit proofs that should instead use the
  dedicated CI exit path from Infra I0.1.

Implementation tasks:
- Provide a consistent halt function (e.g., `cpu_halt_forever()`).
- Route Rust panic handling and the normal end-of-flow path to the same halt primitive or to
  equally strict halt semantics.
- Keep a release/defense-safe infinite halt loop even if CI/test builds use a controlled PASS/FAIL
  exit path instead.

Acceptance criteria:
- After printing, kernel halts without rebooting or triple faulting.
- The halt path does not return to random code.
- The release build has an explicit halt loop in source and in the linked artifact.
- CI/test automation can still terminate deterministically without weakening the release halt path.

Implementation scope:
- `ASM` or `RUST` (but must compile to `cli/hlt` loop)

Proof / tests (definition of done):
- WP-M4.3-1 (halt loop exists in source): `rg -n "(cli\\s*;\\s*)?hlt" -S src/arch/i386/boot.asm src`
- WP-M4.3-2 (release artifact contains the halt pattern in the boot/Rust path): `objdump -d build/kernel-i386.bin | rg -n "cli|hlt"`
- WP-M4.3-3 (panic path converges to a halt primitive): `rg -n "panic_handler|halt_forever|hlt" -S src`
- WP-M4.3-4 (repo proof script covers halt behavior): `bash scripts/boot-tests/halt-behavior.sh i386 rust-kmain-path-halts`, `bash scripts/boot-tests/halt-behavior.sh i386 asm-boot-path-halts`, `bash scripts/boot-tests/halt-behavior.sh i386 panic-handler-halts`, `bash scripts/boot-tests/halt-behavior.sh i386 release-kmain-disassembly-halts`

Stability / adversarial proofs (recommended in visible CI output):
- AT-M4.3-1 (release halt path remains separate from the CI PASS/FAIL exit path): `rg -n "KFS_TEST|0xf4|hlt" -S src/arch/i386/boot.asm src`
  Why it matters: the test harness may intentionally exit QEMU, but the shipped kernel still needs
  a real halt loop.
- AT-M4.3-2 (Rust and ASM both end in explicit terminal behavior): inspect `src/kernel/kmain.rs`
  and `src/arch/i386/boot.asm` for non-returning halt loops
  Why it matters: if `kmain` ever returns accidentally, the CPU should still land in a safe halt.

Negative / rejection proofs (real bad-terminal-behavior cases, not mocks):
- RT-M4.3-1 (rejects a release path with no halt loop): temporarily remove the halt loop and confirm the source/artifact proof fails
- RT-M4.3-2 (rejects an unintended reboot/triple-fault path): boot QEMU with `-no-reboot -no-shutdown` and confirm the kernel does not reset when the normal path completes
- MANUAL-M4.3-1 (no reboot): run QEMU with `-no-reboot -no-shutdown` and confirm it does not reset; it halts as intended
- AUTO-M4.3-1 (current CI proof): use `bash scripts/boot-tests/runtime-markers.sh i386 runtime-completes-early-init` for the test build’s controlled PASS path while preserving the release halt loops proven by `scripts/boot-tests/halt-behavior.sh`

### Definition of Done (M4)
- Rust `kmain` is the real release entry target from ASM boot.
- The running kernel validates its earliest runtime assumptions before normal work.
- The kernel stops in a predictable, non-returning way at the end of the minimal flow.
- The epic is backed by multiple proof classes: workflow/artifact checks, runtime proofs,
  stability/adversarial checks, and explicit rejection/failure tests.

---

## Base Epic M5: Basic Kernel Library (Helpers)

#### Subject basis
- Chapter II requires "a basic kernel library, with basics functions and types".
- Chapter III.2.2 forbids linking the kernel against any existing library on the host.
- Chapter IV.0.1 says that, once boot/link/basic kernel code exist, the kernel may add helpers
  such as kernel types and basic functions like `strlen` and `strcmp`.

#### Current repo truth
- Status: exists now
  - `src/kernel/string.rs`
  - `src/kernel/string/string_impl.rs`
  - `tests/host_string.rs`
  - `scripts/tests/unit/string-helpers.sh`
- Status: exists now
  - raw `strlen` and `strcmp` loops exist in `src/kernel/string/string_impl.rs`
- Status: missing now
  - `src/kernel/types.rs`
  - `src/kernel/types/*`
  - `tests/host_types.rs`
  - `scripts/tests/unit/type-architecture.sh`
  - `scripts/boot-tests/type-architecture.sh`
  - `scripts/rejection-tests/type-architecture-rejections.sh`
- Status: missing now
  - `kfs_strlen`
  - `kfs_strcmp`
  - any real release-path string-helper integration
  - `scripts/boot-tests/string-runtime.sh`
  - `scripts/rejection-tests/string-rejections.sh`
- Status: missing now
  - the full memory-helper family:
    - `src/kernel/memory.rs`
    - `src/kernel/memory/memory_impl.rs`
    - `tests/host_memory.rs`
    - `scripts/tests/unit/memory-helpers.sh`
    - `scripts/boot-tests/memory-runtime.sh`
    - `scripts/rejection-tests/memory-rejections.sh`
- Status: exists now
  - the current string implementation exports only `kfs_string_helpers_marker`, not the real helper
    ABI
- Status: exists now
  - current host tests cover only basic empty/normal/equality/prefix/ordering cases
- Status: exists now
  - current string implementation uses volatile reads for ordinary RAM strings; that is a design
    mismatch with the intended helper contract

#### Target end-state
- Status: build now
  - a real in-repo helper layer with explicit module, type, and ABI rules
  - `M5.1` scaffold and immediate semantic types:
    - `Port(u16)`
    - `KernelRange { start, end }`
  - `M5.2` mandatory string family:
    - `strlen`
    - `strcmp`
    - `kfs_strlen`
    - `kfs_strcmp`
  - matching `UT/WP/SM/AT/RT` proof assets for `M5.1` and `M5.2`
- Status: build now
  - epic closure also requires `M5.3`:
    - `memcpy`
    - `memset`
    - `kfs_memcpy`
    - `kfs_memset`
    - matching `UT/WP/SM/AT/RT` proof assets
- Status: define now, integrate later
  - semantic-type ownership for later domains:
    - `ColorCode(u8)`
    - `VgaCell(u16)`
    - `CursorPos { row, col }`
    - `PhysAddr(usize)`
    - `VirtAddr(usize)`
    - `PageFrame(usize)`
    - `PageCount(usize)`
    - `Pid(u32)`
    - `Fd(u32)`
    - `KernelError`
- Status: future only
  - standalone `libk`
  - allocator-backed helper APIs
  - user-space-facing helper boundaries
  - rich text/string abstractions
  - `memmove` and other non-minimal helper families

#### Intent
- Establish the first kernel-owned freestanding helper layer between `M4` and `M6`.
- Decide the helper-layer architecture once so later families do not reinvent files, ABI, and type
  rules.
- Split ownership cleanly:
  - `M5.1`: scaffold, semantic-type entry point, and low-level ABI conventions
  - `M5.2`: mandatory string helpers named by the subject
  - `M5.3`: derived memory helpers needed for later scaling

#### Architecture decision
- Decision:
  - Keep the first helper layer inside the kernel tree for KFS_1 rather than introducing a separate
    `libk` project now.
  - Why:
    - the subject requires a kernel-owned library, not a separate package boundary
  - Source:
    - `docs/subject.pdf`
    - OSDev Sysroot
    - Linux From Scratch
  - Immediate consumer:
    - `string`
  - Future consumer:
    - `memory`, `screen`, and later subsystems
- Decision:
  - Use one public type facade plus domain modules for semantic kernel types.
  - Why:
    - later kernel growth needs one discoverable type entry point without collapsing into alias-only
      noise
  - Source:
    - repo-derived from the subject plus OSDev Rust / Port I/O / Printing To Screen
  - Immediate consumer:
    - `Port`, `KernelRange`
  - Future consumer:
    - VGA, paging, process, and fs layers
- Decision:
  - Use one public family file plus one private leaf implementation file per helper family.
  - Why:
    - this is the smallest structure that still separates Rust-facing API, exported low-level ABI,
      and leaf algorithms
  - Source:
    - repo-derived from subject constraints plus OSDev Sysroot / C Library guidance
  - Immediate consumer:
    - `string`
  - Future consumer:
    - `memory` and later helper families
- Decision:
  - Keep the low-level helper ABI narrow, explicit, and artifact-verifiable.
  - Why:
    - early-kernel exported helpers must stay freestanding, stable, and easy to prove in the final
      ELF
  - Source:
    - `docs/subject.pdf`
    - OSDev Rust
    - OSDev C Library
    - Linux From Scratch
  - Immediate consumer:
    - exported `kfs_*` helper symbols
  - Future consumer:
    - later ASM/cross-boundary consumers and artifact/runtime proofs

#### Implementation contract
- Build now:
  - `M5.1` scaffold and immediate semantic types
  - `M5.2` full string-helper family
  - epic closure also requires `M5.3`
- Define now, integrate later:
  - later semantic-type ownership and first consumer for screen, memory, process, fs, and shared
    error domains
- Future only:
  - standalone `libk`
  - richer helper families beyond the minimal kernel foundation

#### Data / ABI conventions
- Primitive/core-compatible scalar vocabulary:
  - `usize` for lengths, counts, indices, and address-sized arithmetic
  - `u8` for bytes, character bytes, fill values, and packed byte fields
  - `u16` for x86 ports and packed two-byte hardware cells
  - `u32` for fixed 32-bit hardware/protocol values and later stable kernel IDs
  - `i32` for tri-state comparison or low-level status returns where sign matters
  - raw pointers for low-level memory/string boundaries
- Exported low-level helper ABI rules:
  - symbol prefix: `kfs_`
  - `#[no_mangle] pub unsafe extern "C" fn ...`
  - primitive/core-compatible scalars and raw pointers only
  - no references, slices, `String`, `Vec`, `Option`, `Result`, trait objects, or allocator-backed
    types
- Semantic-type layout rules:
  - single-scalar semantic wrappers use `#[repr(transparent)]`
  - multi-field structural types use `#[repr(C)]`

#### Integration contract
- Immediate runtime consumers:
  - serial/port I/O path uses `Port`
  - runtime layout-span consumers use `KernelRange` instead of naked `(start, end)` pairs
  - `kmain` owns the first string-helper sanity path until `M6` becomes the first natural string
    consumer
  - `kmain` owns the first memory-helper sanity path if `M5.3` exists and no more natural consumer
    exists yet
- Next subsystem consumers:
  - `M6` for VGA-related types and helper consumers
  - later memory/process/fs subjects for the rest of the semantic type program
- Ownership boundary:
  - `M4` still owns early-init/failure-path infrastructure
  - `M5` owns the helper contracts and their kernel integration points
  - `M6` owns the first ordinary screen/text consumer

#### Acceptance criteria
- The repo contains a real in-repo helper layer and not a paper-only helper concept.
- The helper layer has explicit module, semantic-type, and ABI rules.
- `M5.1` states exactly what is built now and what is only reserved for later owner epics.
- `M5.2` is specified as a real release-path dependency, not just linked dead code.
- `M5.3` is either specified and implemented to the same proof standard or left explicitly open.
- Current repo truth is kept separate from target end-state.

#### Proof matrix
- `WP-M5-1`
  - Assertion:
    - the repo exposes the required helper scaffold and immediate semantic-type facade
  - Evidence:
    - `bash scripts/tests/unit/type-architecture.sh i386 helper-boundary-files-exist`
    - `bash scripts/tests/unit/type-architecture.sh i386 helper-abi-uses-primitive-core-types`
  - Failure caught:
    - paper-only helper architecture or undefined low-level ABI rules
  - Status:
    - to add
- `WP-M5-2`
  - Assertion:
    - the release kernel exports the mandatory string-helper ABI and the repo avoids hosted string
      fallbacks
  - Evidence:
    - `bash scripts/tests/unit/string-helpers.sh i386 release-kernel-exports-kfs-strlen`
    - `bash scripts/tests/unit/string-helpers.sh i386 release-kernel-exports-kfs-strcmp`
    - `bash scripts/tests/unit/string-helpers.sh i386 rust-avoids-extern-strlen`
    - `bash scripts/tests/unit/string-helpers.sh i386 rust-avoids-extern-strcmp`
  - Failure caught:
    - `M5` claimed complete while the final artifact still lacks the real string-helper ABI or
      still depends on host-library string helpers
  - Status:
    - to add
- `SM-M5-3`
  - Assertion:
    - the running kernel reaches the mandatory string-helper path and emits ordered success markers
  - Evidence:
    - `bash scripts/boot-tests/string-runtime.sh i386 runtime-confirms-string-helpers`
    - `bash scripts/boot-tests/string-runtime.sh i386 runtime-string-markers-are-ordered`
  - Failure caught:
    - helpers linked but dead in the running kernel or only partially integrated
  - Status:
    - to add

#### Common bad implementations
- Paper-only helper architecture with no real boundaries
- Helpers linked but not consumed by the running kernel
- Hosted fallbacks hidden behind the build
- Cosmetic alias types instead of real semantic kernel types
- Under-specified helper contracts that later subsystems cannot safely build on

#### Explicit exclusions
- `M5` does not own entry, layout/BSS validation, or halt behavior; those remain in `M4`.
- `M5` does not own the first real screen writer; that remains in `M6`.
- `M5` does not define a user-space-ready libc or allocator-backed helper layer.

#### Source basis
- `docs/subject.pdf`
- OSDev Rust: <https://wiki.osdev.org/Rust>
- OSDev Sysroot: <https://wiki.osdev.org/Sysroot>
- OSDev C Library: <https://wiki.osdev.org/C_Library>
- OSDev Port I/O: <https://wiki.osdev.org/Port_IO>
- OSDev Printing To Screen: <https://wiki.osdev.org/Printing_To_Screen>
- OSDev Text Mode Cursor: <https://wiki.osdev.org/Text_Mode_Cursor>
- OSDev Why do I need a Cross Compiler?: <https://wiki.osdev.org/Why_do_I_need_a_Cross_Compiler>
- Linux From Scratch book: <https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/LFS-BOOK-13.0-NOCHUNKS.html>

### Feature M5.1: Helper-library scaffold, type architecture, and ABI/data conventions

#### Subject basis
- The subject requires a basic kernel library with basic functions and types.
- The subject forbids linking the kernel against host libraries.
- The subject does not define the helper-module architecture, helper ABI, or kernel-type tree.
  Those are repo design decisions that must still align with freestanding-kernel constraints.

#### Current repo truth
- Status: exists now
  - `src/kernel/string.rs`
  - `src/kernel/string/string_impl.rs`
- Status: missing now
  - `src/kernel/types.rs`
  - `src/kernel/types/*`
  - `tests/host_types.rs`
  - `scripts/tests/unit/type-architecture.sh`
  - `scripts/boot-tests/type-architecture.sh`
  - `scripts/rejection-tests/type-architecture-rejections.sh`
- Status: exists now
  - the repo already has the start of a public/private helper split for the string family
- Status: missing now
  - any explicit type facade
  - any semantic type implementation
  - any enforced low-level ABI policy beyond ad hoc current code shape

#### Target end-state
- Status: build now
  - `src/kernel/types.rs`
  - `src/kernel/types/port.rs`
  - `src/kernel/types/range.rs`
  - `tests/host_types.rs`
  - `scripts/tests/unit/type-architecture.sh`
  - `scripts/boot-tests/type-architecture.sh`
  - `scripts/rejection-tests/type-architecture-rejections.sh`
  - a single helper-family layout rule for all current/future helper families
- Status: define now, integrate later
  - later semantic-type ownership is recorded, not built here:
    - VGA domain -> first owner: `M6`
    - memory domain -> first owner: later memory/paging epic
    - process domain -> first owner: later task/process epic
    - fs domain -> first owner: later fs/vfs epic
    - shared error domain -> first owner: first later epic with multiple recoverable subsystem
      errors
- Status: future only
  - semantic types that are not yet owned by a real subsystem implementation
  - any alias-only primitive wrapper layer

#### Intent
- Define the permanent helper-library scaffold that later families plug into.
- Define the low-level helper ABI once so later helper families follow one convention.
- Build only the semantic types that have immediate kernel consumers now.
- Reserve later semantic types explicitly so later epics do not reinvent names and ownership.

#### Architecture decision
- Decision:
  - Use one public type facade at `src/kernel/types.rs`.
  - Why:
    - the repo needs one discoverable access point for semantic types
  - Source:
    - repo-derived from the subject plus OSDev Rust and Sysroot
  - Immediate consumer:
    - `Port`, `KernelRange`
  - Future consumer:
    - VGA, memory, task, and fs layers
- Decision:
  - Keep built-now and reserved-later types separated by domain ownership.
  - Why:
    - the feature must tell the reader what to build now without pretending every later domain
      type already belongs in the tree
  - Source:
    - repo-derived from later-kernel scaling constraints plus OSDev Port I/O / VGA guidance
  - Immediate consumer:
    - `port`, `range`
  - Future consumer:
    - `vga`, `addr`, `page`, `task`, `fs`, `error`
- Decision:
  - Use one public family file and one private leaf implementation file per helper family.
  - Why:
    - public Rust API, exported low-level ABI, and leaf algorithms must not collapse into one
      undocumented surface
  - Source:
    - repo-derived from subject constraints plus OSDev Sysroot / C Library direction
  - Immediate consumer:
    - `string`
  - Future consumer:
    - `memory` and later helper families
- Decision:
  - Use primitive/core-compatible scalars directly in the low-level ABI and reserve semantic
    wrappers for real domain meaning.
  - Why:
    - alias-only primitive types are noise; real semantic wrappers buy clarity and invariants
  - Source:
    - OSDev Rust
    - repo-derived architectural scaling constraint
  - Immediate consumer:
    - helper ABI and `Port` / `KernelRange`
  - Future consumer:
    - typed VGA, address, page, task, and fs domains

#### Implementation contract
- Build now:
  - `src/kernel/types.rs`
  - `src/kernel/types/port.rs`
  - `src/kernel/types/range.rs`
  - `Port(u16)`
  - `KernelRange { start, end }`
  - `tests/host_types.rs`
  - `scripts/tests/unit/type-architecture.sh`
  - `scripts/boot-tests/type-architecture.sh`
  - `scripts/rejection-tests/type-architecture-rejections.sh`
  - one consistent helper-family naming/layout rule:
    - family `string` -> `src/kernel/string.rs` + `src/kernel/string/string_impl.rs`
    - family `memory` -> `src/kernel/memory.rs` + `src/kernel/memory/memory_impl.rs`
    - any later helper family follows the same `src/kernel/<name>.rs` plus
      `src/kernel/<name>/<name>_impl.rs` pattern
- Define now, integrate later:
  - record later semantic-type ownership only:
    - VGA domain -> `ColorCode(u8)`, `VgaCell(u16)`, `CursorPos { row, col }` -> `M6`
    - memory domain -> `PhysAddr(usize)`, `VirtAddr(usize)`, `PageFrame(usize)`,
      `PageCount(usize)` -> later memory/paging epic
    - process domain -> `Pid(u32)` -> later task/process epic
    - fs domain -> `Fd(u32)` -> later fs/vfs epic
    - shared error domain -> `KernelError` -> later subsystem-error epic
- Future only:
  - any semantic type not tied to an owned current or later kernel domain

#### Data / ABI conventions
- Primitive/core-compatible scalar vocabulary used directly:
  - `usize`
  - `u8`
  - `u16`
  - `u32`
  - `i32`
  - raw pointers
- Meaning of that vocabulary in this repo:
  - `usize`: lengths, counts, indices, address-sized arithmetic
  - `u8`: bytes, character bytes, fill values, packed byte fields
  - `u16`: x86 ports and packed VGA cells
  - `u32`: fixed 32-bit hardware/protocol values and later stable kernel IDs
  - `i32`: tri-state comparison/status values
  - raw pointers: exported low-level helper boundaries only
- Exported low-level helper ABI must:
  - use the `kfs_` prefix
  - use `#[no_mangle] pub unsafe extern "C" fn ...`
  - use only primitive/core-compatible scalars and raw pointers
- Exported low-level helper ABI must not:
  - expose references
  - expose slices
  - expose `String`
  - expose `Vec`
  - expose `Option`
  - expose `Result`
  - expose trait objects
  - expose allocator-backed types
- Semantic-type layout rules:
  - single-scalar semantic wrappers use `#[repr(transparent)]`
  - multi-field structural types use `#[repr(C)]`
  - `Port` is the required built-now transparent wrapper
  - `KernelRange` is the required built-now C-layout structural type

#### Integration contract
- Immediate runtime/use path:
  - serial and x86 port I/O paths consume `Port`
  - runtime layout-span consumers consume `KernelRange` instead of naked `(start, end)` pairs
- Deferred runtime/use path:
  - `M6` consumes VGA-domain types
  - later memory/process/fs subjects consume the later semantic types
- Boundary rule:
  - other kernel code calls public family modules and public semantic types
  - other kernel code does not import private helper implementation files directly

#### Acceptance criteria
- The repo has one discoverable type facade and one helper-family layout rule.
- `Port` and `KernelRange` are real built-now types, not only names in prose.
- The low-level helper ABI is defined precisely enough that later families can reuse it without
  guessing.
- Later semantic types are clearly marked as reserved ownership, not implied present deliverables
  or placeholder modules to build now.
- No alias-only primitive layer exists.
- Other kernel code calls public helper boundaries, not private helper implementation files.

#### Proof matrix
- `UT-M5.1-1`
  - Assertion:
    - `Port` preserves wrapped value and supports register-offset math correctly
  - Evidence:
    - `tests/host_types.rs`
    - `scripts/tests/unit/type-architecture.sh i386 port-host-unit-tests-pass`
  - Failure caught:
    - width drift and wrong register-offset behavior
  - Status:
    - to add
- `UT-M5.1-2`
  - Assertion:
    - `KernelRange` enforces empty/containment/length semantics correctly
  - Evidence:
    - `tests/host_types.rs`
    - `scripts/tests/unit/type-architecture.sh i386 kernel-range-host-unit-tests-pass`
  - Failure caught:
    - off-by-one and bad range-math behavior
  - Status:
    - to add
- `WP-M5.1-3`
  - Assertion:
    - the repo exposes the required type facade and helper-family file layout
  - Evidence:
    - `scripts/tests/unit/type-architecture.sh i386 helper-boundary-files-exist`
  - Failure caught:
    - fake architecture with no discoverable public/private split
  - Status:
    - to add
- `WP-M5.1-4`
  - Assertion:
    - the exported helper ABI uses only primitive/core-compatible scalars and raw pointers
  - Evidence:
    - `scripts/tests/unit/type-architecture.sh i386 helper-abi-uses-primitive-core-types`
  - Failure caught:
    - hosted/allocator-backed types leaking into the low-level ABI
  - Status:
    - to add
- `WP-M5.1-5`
  - Assertion:
    - the kernel helper/type layer avoids `std` and alias-only primitive wrappers
  - Evidence:
    - `scripts/tests/unit/type-architecture.sh i386 kernel-helper-code-avoids-std`
    - `scripts/tests/unit/type-architecture.sh i386 no-alias-only-primitive-layer`
  - Failure caught:
    - hosted drift and fake type architecture
  - Status:
    - to add
- `WP-M5.1-6`
  - Assertion:
    - built-now semantic types and exported helper wrappers keep the required repr and ABI markers
  - Evidence:
    - `scripts/tests/unit/type-architecture.sh i386 port-uses-repr-transparent`
    - `scripts/tests/unit/type-architecture.sh i386 kernel-range-uses-repr-c`
    - `scripts/tests/unit/type-architecture.sh i386 helper-wrappers-use-extern-c-and-no-mangle`
  - Failure caught:
    - layout drift and ABI drift that break later low-level consumers
  - Status:
    - to add
- `SM-M5.1-7`
  - Assertion:
    - runtime serial/port and layout paths still work through the built-now semantic types
  - Evidence:
    - `scripts/boot-tests/type-architecture.sh i386 runtime-serial-path-works-with-port`
    - `scripts/boot-tests/type-architecture.sh i386 runtime-layout-path-works-with-kernel-range`
  - Failure caught:
    - types defined in isolation but not integrated into real kernel paths
  - Status:
    - to add
- `AT-M5.1-8`
  - Assertion:
    - public kernel code does not bypass helper public surfaces or drift back to raw scalar use
      where `Port` and `KernelRange` are required
  - Evidence:
    - `scripts/tests/unit/type-architecture.sh i386 helper-private-impl-not-imported-directly`
    - `scripts/tests/unit/type-architecture.sh i386 serial-path-uses-port-type`
    - `scripts/tests/unit/type-architecture.sh i386 layout-path-uses-kernel-range-type`
  - Failure caught:
    - architectural collapse of public/private boundaries and semantic-type bypass drift
  - Status:
    - to add
- `RT-M5.1-9`
  - Assertion:
    - hosted-type drift, alias-only primitive drift, missing repr markers, and private-helper
      imports fail the repo gates
  - Evidence:
    - `scripts/rejection-tests/type-architecture-rejections.sh i386 std-in-helper-layer-fails`
    - `scripts/rejection-tests/type-architecture-rejections.sh i386 alias-only-primitive-layer-fails`
    - `scripts/rejection-tests/type-architecture-rejections.sh i386 port-missing-repr-transparent-fails`
    - `scripts/rejection-tests/type-architecture-rejections.sh i386 kernel-range-missing-repr-c-fails`
    - `scripts/rejection-tests/type-architecture-rejections.sh i386 helper-wrapper-missing-extern-c-fails`
    - `scripts/rejection-tests/type-architecture-rejections.sh i386 private-helper-import-fails`
  - Failure caught:
    - the scaffold eroding silently over time
  - Status:
    - to add

#### Common bad implementations
- Saying "use Rust primitives" without defining the helper ABI at all
- Creating a fake alias-only `types` layer
- Letting other kernel code import private helper implementation files
- Creating placeholder modules for later semantic types and pretending that counts as integration

#### Explicit exclusions
- `M5.1` does not implement string-helper or memory-helper semantics.
- `M5.1` does not require every later semantic type to be integrated now.
- `M5.1` does not authorize allocator-backed or hosted abstractions in the low-level helper ABI.
- `M5.1` does not create placeholder modules for later semantic types just to make the tree look
  complete.

#### Source basis
- `docs/subject.pdf`
- OSDev Rust: <https://wiki.osdev.org/Rust>
- OSDev Sysroot: <https://wiki.osdev.org/Sysroot>
- OSDev C Library: <https://wiki.osdev.org/C_Library>
- OSDev Port I/O: <https://wiki.osdev.org/Port_IO>
- OSDev Printing To Screen: <https://wiki.osdev.org/Printing_To_Screen>
- OSDev Text Mode Cursor: <https://wiki.osdev.org/Text_Mode_Cursor>
- Linux From Scratch book: <https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/LFS-BOOK-13.0-NOCHUNKS.html>

### Feature M5.2: Mandatory string helper family (`strlen`, `strcmp`)

#### Subject basis
- The subject explicitly names `strlen` and `strcmp`.
- The subject also forbids solving this by linking against host libraries.

#### Current repo truth
- Status: exists now
  - raw `strlen` and `strcmp` loops exist in `src/kernel/string/string_impl.rs`
  - basic host tests exist in `tests/host_string.rs`
  - basic unit/source/marker script exists in `scripts/tests/unit/string-helpers.sh`
- Status: missing now
  - `kfs_strlen`
  - `kfs_strcmp`
  - release-path string-helper integration
  - `scripts/boot-tests/string-runtime.sh`
  - `scripts/rejection-tests/string-rejections.sh`
- Status: exists now
  - `src/kernel/string.rs` exports only `kfs_string_helpers_marker`
- Status: exists now
  - current host tests do not yet cover embedded-NUL stop behavior or high-byte ordering
- Status: exists now
  - current implementation uses volatile reads for ordinary RAM strings

#### Target end-state
- Status: build now
  - `kfs_strlen`
  - `kfs_strcmp`
  - richer host tests covering empty, normal, embedded-NUL, equality, prefix, first-difference,
    and high-byte ordering cases
  - `scripts/boot-tests/string-runtime.sh`
  - `scripts/rejection-tests/string-rejections.sh`
  - one real release-path helper sanity path until `M6` becomes the natural string consumer
- Status: define now, integrate later
  - later screen/text subsystem as the primary ordinary consumer after `M6`
- Status: future only
  - null-pointer recovery
  - unterminated-buffer recovery
  - user-buffer validation
  - UTF-8 or rich text semantics

#### Intent
- Implement the first mandatory reusable helper family in the kernel-owned helper layer.
- Define an honest string contract for this project stage:
  valid NUL-terminated byte strings in ordinary kernel-owned RAM.
- Prove both helper semantics and release-path integration.
- Reuse the `M5.1` helper-family architecture and low-level ABI conventions without redefining them per helper.

#### Architecture decision
- Decision:
  - `M5.2` must reuse the `M5.1` helper-family architecture and low-level ABI conventions unchanged
  - Why:
    - the first concrete helper family should prove that `M5.1` is a reusable kernel-library scaffold, not a one-off policy note
  - Source:
    - `M5.1` in this repo
    - repo-derived architecture ownership rule
  - Immediate consumer:
    - string family
  - Future consumer:
    - memory and later helper families
- Decision:
  - keep the public Rust family API and exported wrappers in `src/kernel/string.rs`
  - Why:
    - one file should define the string family’s public/internal kernel surface and exported helper
      ABI
  - Source:
    - repo-derived from M5.1 architecture plus OSDev Sysroot / C Library
  - Immediate consumer:
    - `kmain` sanity path
  - Future consumer:
    - `M6` screen/text path
- Decision:
  - keep the leaf algorithms in `src/kernel/string/string_impl.rs`
  - Why:
    - pure helper semantics need an isolated leaf file for unit testing and review
  - Source:
    - repo-derived from subject constraints plus OSDev C Library direction
  - Immediate consumer:
    - host tests and wrappers
  - Future consumer:
    - later string-adjacent helpers
- Decision:
  - model these helpers as ordinary RAM byte-string helpers, not MMIO helpers
  - Why:
    - string helpers must not blur the line between normal memory and device memory
  - Source:
    - OSDev Rust
    - repo-derived architecture boundary
  - Immediate consumer:
    - current kernel strings
  - Future consumer:
    - screen/debug/parser code
- Decision:
  - specify `strcmp` by sign-compatible ordering, not exact subtraction value
  - Why:
    - the kernel needs ordering semantics, not a falsely over-specified arithmetic contract
  - Source:
    - repo-derived from the role of `strcmp` plus standard freestanding string behavior
  - Immediate consumer:
    - host tests and release sanity path
  - Future consumer:
    - later parser/debug/text code

#### Implementation contract
- Build now:
  - reuse the `M5.1` family pattern unchanged:
    - public family file: `src/kernel/string.rs`
    - private leaf file: `src/kernel/string/string_impl.rs`
    - exported low-level wrappers follow the `M5.1` ABI rules
    - other kernel code must not import `src/kernel/string/string_impl.rs` directly
  - `src/kernel/string/string_impl.rs`
    - `strlen(ptr: *const u8) -> usize`
    - `strcmp(lhs: *const u8, rhs: *const u8) -> i32`
  - `src/kernel/string.rs`
    - public Rust family API
    - `kfs_strlen(ptr: *const u8) -> usize`
    - `kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32`
    - optional marker symbol only as secondary proof aid
  - `tests/host_string.rs`
  - `scripts/tests/unit/string-helpers.sh`
  - `scripts/boot-tests/string-runtime.sh`
  - `scripts/rejection-tests/string-rejections.sh`
  - one release-path string-helper sanity path owned by `kmain`
- Define now, integrate later:
  - `M6` screen/text layer as the first natural subsystem consumer
- Future only:
  - richer string/text abstractions

#### Data / ABI conventions
- `strlen`
  - input: pointer to a valid NUL-terminated byte string in kernel-owned RAM
  - output: number of bytes before the first NUL terminator
- `strcmp`
  - inputs: pointers to valid NUL-terminated byte strings in kernel-owned RAM
  - output: `0` for equality, negative for left smaller, positive for left greater
  - tests must check sign semantics, not exact subtraction magnitude
- Out of contract:
  - null pointers
  - missing terminators
  - user memory
  - UTF-8/text semantics
  - MMIO/device memory
- Required exported wrapper signatures:
  - `kfs_strlen(ptr: *const u8) -> usize`
  - `kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32`

#### Sub-spec M5.2.a: `strlen`

##### Subject basis
- The subject explicitly names `strlen` as part of the mandatory helper layer.
- The subject does not define performance tier, alignment strategy, or failure recovery semantics.
- Repo-derived choice:
  - completion requires a correct freestanding kernel-owned implementation first
  - internal optimization is allowed only if it preserves the same ABI, contract, and proof surface

##### Current repo truth
- Status: exists now
  - raw `strlen(ptr: *const u8) -> usize` exists in `src/kernel/string/string_impl.rs`
  - host tests cover empty and ordinary strings in `tests/host_string.rs`
- Status: missing now
  - `kfs_strlen(ptr: *const u8) -> usize`
  - embedded-NUL stop proof
  - runtime proof that the release path actually reaches `kfs_strlen`
- Status: exists now
  - the current implementation is a simple byte-at-a-time loop
- Status: exists now
  - the current implementation reads ordinary RAM through `read_volatile`, which does not match the intended contract

##### Target end-state
- Status: build now
  - a kernel-owned `kfs_strlen(ptr: *const u8) -> usize`
  - a raw leaf `strlen(ptr: *const u8) -> usize` in `src/kernel/string/string_impl.rs`
  - host tests for empty, ordinary, embedded-NUL, unaligned-start, and longer-prefix cases
  - source/build checks proving the release kernel exports `kfs_strlen`
  - runtime proof that the release path reaches `kfs_strlen` before later normal flow
- Status: define now, integrate later
  - an optional internal word-at-a-time scan strategy hidden behind the same ABI and proof surface
- Status: future only
  - arch-specific assembly fast paths
  - vectorized scans
  - page-fault-safe or user-buffer-safe traversal

##### Intent
- Define the exact semantic contract for the kernel’s first string-length primitive.
- Make `strlen` correct and reusable before making it clever.
- Allow modest internal optimization later without changing callers, exports, or proofs.
- Reuse the `M5.1` family scaffold and ABI rules exactly as the `strlen` ownership boundary.

##### Architecture decision
- Decision:
  - keep `strlen` as a leaf helper behind the string-family public API and exported wrapper
  - Why:
    - callers should depend on the family API and `kfs_` ABI, not on the leaf implementation directly
  - Source:
    - `M5.1` architecture in this repo
    - OSDev C Library
  - Immediate consumer:
    - `kmain` string sanity path
  - Future consumer:
    - `M6` text/screen code and later parser/debug code
- Decision:
  - treat the scalar byte loop as the required completion baseline
  - Why:
    - correctness and proof coverage matter more than micro-optimization at this stage
  - Source:
    - repo-derived kernel bring-up constraint
    - musl `strlen.c`
  - Immediate consumer:
    - current host and runtime proofs
  - Future consumer:
    - later optimized internal implementation
- Decision:
  - allow an optional internal word-at-a-time optimization only as an implementation detail
  - Why:
    - `strlen` has a credible portable optimization path, but the optimization must not become the external contract
  - Source:
    - musl `strlen.c`
  - Immediate consumer:
    - leaf implementation only
  - Future consumer:
    - later performance tuning without ABI churn

##### Implementation contract
- Build now:
  - reuse the `M5.1` helper boundary:
    - public family entry stays in `src/kernel/string.rs`
    - leaf algorithm stays in `src/kernel/string/string_impl.rs`
    - exported low-level wrapper follows the `M5.1` ABI rules for primitive-only signatures
  - raw leaf: `strlen(ptr: *const u8) -> usize`
  - wrapper/export: `kfs_strlen(ptr: *const u8) -> usize`
  - host cases for:
    - empty string
    - ordinary string
    - embedded-NUL stop-at-first-NUL
    - unaligned starting pointer
    - longer string crossing a natural word boundary
  - source/build checks for:
    - wrapper export
    - release-kernel symbol export
    - no volatile ordinary-memory reads
- Define now, integrate later:
  - optional internal word-at-a-time scan with a byte-prefix phase for alignment
- Future only:
  - assembly-specific micro-optimizations

##### Data / ABI conventions
- Input:
  - pointer to a valid NUL-terminated byte string in kernel-owned ordinary RAM
- Output:
  - byte count before the first NUL terminator
- Required behavioral rules:
  - stop exactly at the first NUL
  - return `0` for an empty string
  - count bytes, not characters or text-codepoints
- Internal implementation rules:
  - ordinary reads only
  - no volatile reads for ordinary RAM strings
  - any optimization must preserve identical observable results for the valid-input contract

##### Runtime / integration path
- `kmain` is the first runtime owner of the `strlen` sanity path.
- The release runtime path must call `kfs_strlen` before `kfs_strcmp`.
- The runtime proof must expose `STRLEN_OK` before the later string-family success marker.

##### Acceptance criteria
- The repo exports `kfs_strlen(ptr: *const u8) -> usize`.
- `strlen` returns the number of bytes before the first NUL terminator for valid kernel-owned strings.
- Embedded NULs stop the scan at the first NUL.
- The implementation does not use volatile reads for ordinary RAM strings.
- The running kernel proves that `kfs_strlen` is reached in the real release path.

##### Proof matrix
- `UT-M5.2.a-1`
  - Assertion:
    - `strlen` returns correct lengths for empty and ordinary strings
  - Evidence:
    - `tests/host_string.rs`
    - `scripts/tests/unit/string-helpers.sh i386 host-strlen-unit-tests-pass`
  - Failure caught:
    - broken loop termination and wrong length counting
  - Status:
    - exists now
- `UT-M5.2.a-2`
  - Assertion:
    - `strlen` stops at the first NUL even when later bytes remain non-zero
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 host-strlen-embedded-nul-stops-first`
  - Failure caught:
    - scanning past the first terminator
  - Status:
    - to add
- `AT-M5.2.a-3`
  - Assertion:
    - `strlen` behaves correctly for unaligned starts and strings that cross a natural word boundary
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 host-strlen-unaligned-start`
    - `scripts/tests/unit/string-helpers.sh i386 host-strlen-word-boundary`
  - Failure caught:
    - alignment-sensitive off-by-one or premature stop bugs
  - Status:
    - to add
- `WP-M5.2.a-4`
  - Assertion:
    - the repo exports `kfs_strlen` in source and in the release kernel artifact
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 rust-exports-kfs-strlen`
    - `scripts/tests/unit/string-helpers.sh i386 release-kernel-exports-kfs-strlen`
  - Failure caught:
    - helper logic existing only as an internal function with no stable low-level ABI
  - Status:
    - to add
- `SM-M5.2.a-5`
  - Assertion:
    - the release runtime path reaches `kfs_strlen` and emits `STRLEN_OK`
  - Evidence:
    - `scripts/boot-tests/string-runtime.sh i386 release-kmain-calls-kfs-strlen`
    - `scripts/boot-tests/string-runtime.sh i386 runtime-confirms-strlen`
  - Failure caught:
    - dead code or fake linkage-only proof
  - Status:
    - to add
- `RT-M5.2.a-6`
  - Assertion:
    - a bad `strlen` self-check emits `STRING_HELPERS_FAIL` and stops later normal flow
  - Evidence:
    - `scripts/rejection-tests/string-rejections.sh i386 bad-string-self-check-fails`
  - Failure caught:
    - kernel continuing after a foundational helper mismatch
  - Status:
    - to add

##### Common bad implementations
- Counting the terminating NUL as part of the returned length
- Scanning past the first embedded NUL
- Treating text encoding semantics as part of `strlen`
- Introducing an optimized scan that breaks on unaligned starts
- Using volatile reads for ordinary string memory

##### Explicit exclusions
- `strlen` does not promise null-pointer handling.
- `strlen` does not promise unterminated-buffer recovery.
- `strlen` does not define text encoding semantics.
- `strlen` does not require arch-specific optimization for `M5.2` completion.

##### Source basis
- `docs/subject.pdf`
- OSDev C Library: <https://wiki.osdev.org/C_Library>
- OSDev Sysroot: <https://wiki.osdev.org/Sysroot>
- musl `strlen.c`: <https://git.musl-libc.org/cgit/musl/tree/src/string/strlen.c>

#### Sub-spec M5.2.b: `strcmp`

##### Subject basis
- The subject explicitly names `strcmp` as part of the mandatory helper layer.
- The subject does not define exact arithmetic return values or optimization strategy.
- Repo-derived choice:
  - the kernel only requires sign-compatible ordering semantics for valid kernel-owned byte strings

##### Current repo truth
- Status: exists now
  - raw `strcmp(lhs: *const u8, rhs: *const u8) -> i32` exists in `src/kernel/string/string_impl.rs`
  - host tests cover equality, ordinary ordering, and prefix behavior in `tests/host_string.rs`
- Status: missing now
  - `kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32`
  - high-byte ordering proof
  - runtime proof that the release path actually reaches `kfs_strcmp`
- Status: exists now
  - the current implementation is a scalar byte-by-byte compare
- Status: exists now
  - the current implementation uses volatile reads for ordinary RAM strings

##### Target end-state
- Status: build now
  - a kernel-owned `kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32`
  - a raw leaf `strcmp(lhs: *const u8, rhs: *const u8) -> i32`
  - host tests for equality, prefix, first-difference, empty/non-empty, same-pointer, and high-byte ordering
  - source/build checks proving the release kernel exports `kfs_strcmp`
  - runtime proof that the release path reaches `kfs_strcmp` after `kfs_strlen`
- Status: define now, integrate later
  - an optional same-pointer fast path as an internal optimization only
- Status: future only
  - locale/text-collation semantics
  - UTF-8-aware ordering
  - vectorized or arch-specific comparison paths

##### Intent
- Define the kernel’s first freestanding byte-string ordering primitive.
- Keep the external contract narrow: equality and sign-compatible byte ordering only.
- Prevent over-specifying arithmetic details that later code does not need.
- Reuse the `M5.1` family scaffold and ABI rules exactly as the `strcmp` ownership boundary.

##### Architecture decision
- Decision:
  - keep `strcmp` behind the same family-level public API and exported wrapper structure as `strlen`
  - Why:
    - the string family should expose one consistent public/internal surface and one stable low-level ABI
  - Source:
    - `M5.1` architecture in this repo
    - OSDev C Library
  - Immediate consumer:
    - `kmain` string sanity path
  - Future consumer:
    - `M6` text/screen path and later parser/debug code
- Decision:
  - define success in terms of sign-compatible ordering, not exact difference magnitude
  - Why:
    - callers need ordering semantics; exact subtraction magnitude is an unnecessary and brittle contract
  - Source:
    - repo-derived from freestanding string semantics
  - Immediate consumer:
    - host tests and runtime sanity checks
  - Future consumer:
    - parser/debug/text code
- Decision:
  - compare bytes as unsigned byte values
  - Why:
    - high-byte cases must not depend on platform `char` signedness assumptions
  - Source:
    - standard freestanding string behavior
    - musl `strcmp.c`
  - Immediate consumer:
    - current host tests
  - Future consumer:
    - later binary/text-adjacent code

##### Implementation contract
- Build now:
  - reuse the `M5.1` helper boundary:
    - public family entry stays in `src/kernel/string.rs`
    - leaf algorithm stays in `src/kernel/string/string_impl.rs`
    - exported low-level wrapper follows the `M5.1` ABI rules for primitive-only signatures
  - raw leaf: `strcmp(lhs: *const u8, rhs: *const u8) -> i32`
  - wrapper/export: `kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32`
  - host cases for:
    - equality
    - empty vs empty
    - empty vs non-empty
    - prefix ordering
    - first difference in the first, middle, and later compared byte
    - high-byte ordering (`0x80`, `0xff`, and ASCII combinations)
    - same-pointer equality
  - source/build checks for:
    - wrapper export
    - release-kernel symbol export
    - no volatile ordinary-memory reads
- Define now, integrate later:
  - optional same-pointer fast path
- Future only:
  - locale-aware or UTF-8-aware ordering

##### Data / ABI conventions
- Inputs:
  - two pointers to valid NUL-terminated byte strings in kernel-owned ordinary RAM
- Output:
  - `0` if equal
  - negative if left is smaller
  - positive if left is greater
- Required behavioral rules:
  - ordering is based on the first differing byte or the first NUL terminator
  - tests must check sign, not exact subtraction magnitude
  - byte comparison semantics are unsigned-byte semantics
- Internal implementation rules:
  - ordinary reads only
  - no volatile reads for ordinary RAM strings
  - any optimization must preserve identical sign results for valid inputs

##### Runtime / integration path
- `kmain` is the first runtime owner of the `strcmp` sanity path.
- The release runtime path must call `kfs_strcmp` after `kfs_strlen`.
- The runtime proof must expose `STRCMP_OK` before the later string-family success marker.

##### Acceptance criteria
- The repo exports `kfs_strcmp(lhs: *const u8, rhs: *const u8) -> i32`.
- `strcmp` returns correct sign-compatible ordering for valid kernel-owned byte strings.
- Prefix and high-byte cases are covered by host proofs.
- The implementation does not use volatile reads for ordinary RAM strings.
- The running kernel proves that `kfs_strcmp` is reached in the real release path.

##### Proof matrix
- `UT-M5.2.b-1`
  - Assertion:
    - `strcmp` returns correct sign behavior for equality and ordinary ordering
  - Evidence:
    - `tests/host_string.rs`
    - `scripts/tests/unit/string-helpers.sh i386 host-strcmp-unit-tests-pass`
  - Failure caught:
    - wrong sign behavior for common cases
  - Status:
    - exists now
- `UT-M5.2.b-2`
  - Assertion:
    - `strcmp` handles prefix, empty/non-empty, and same-pointer equality correctly
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 host-strcmp-prefix-and-empty-cases`
    - `scripts/tests/unit/string-helpers.sh i386 host-strcmp-same-pointer`
  - Failure caught:
    - premature equality or wrong terminator handling
  - Status:
    - to add
- `AT-M5.2.b-3`
  - Assertion:
    - `strcmp` uses unsigned-byte ordering for high-byte cases
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 host-strcmp-high-byte-ordering`
  - Failure caught:
    - signed-byte comparison mistakes
  - Status:
    - to add
- `WP-M5.2.b-4`
  - Assertion:
    - the repo exports `kfs_strcmp` in source and in the release kernel artifact
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 rust-exports-kfs-strcmp`
    - `scripts/tests/unit/string-helpers.sh i386 release-kernel-exports-kfs-strcmp`
  - Failure caught:
    - helper logic existing only as an internal function with no stable low-level ABI
  - Status:
    - to add
- `SM-M5.2.b-5`
  - Assertion:
    - the release runtime path reaches `kfs_strcmp` and emits `STRCMP_OK`
  - Evidence:
    - `scripts/boot-tests/string-runtime.sh i386 release-kmain-calls-kfs-strcmp`
    - `scripts/boot-tests/string-runtime.sh i386 runtime-confirms-strcmp`
  - Failure caught:
    - helper linked but not actually used in the running kernel
  - Status:
    - to add
- `RT-M5.2.b-6`
  - Assertion:
    - a bad `strcmp` self-check emits `STRING_HELPERS_FAIL` and stops later normal flow
  - Evidence:
    - `scripts/rejection-tests/string-rejections.sh i386 bad-string-self-check-fails`
    - `scripts/rejection-tests/string-rejections.sh i386 bad-string-stops-before-normal-flow`
  - Failure caught:
    - kernel silently continuing after a foundational comparison-helper mismatch
  - Status:
    - to add

##### Common bad implementations
- Returning exact subtraction values as if they were the required public contract
- Comparing bytes as signed values and getting high-byte order wrong
- Treating prefix cases as equality
- Using volatile reads for ordinary string memory
- Exporting only an internal marker instead of a real `kfs_strcmp` ABI surface

##### Explicit exclusions
- `strcmp` does not define locale or collation semantics.
- `strcmp` does not define UTF-8-aware ordering.
- `strcmp` does not promise null-pointer handling.
- `strcmp` does not require arch-specific optimization for `M5.2` completion.

##### Source basis
- `docs/subject.pdf`
- OSDev C Library: <https://wiki.osdev.org/C_Library>
- OSDev Sysroot: <https://wiki.osdev.org/Sysroot>
- musl `strcmp.c`: <https://git.musl-libc.org/cgit/musl/tree/src/string/strcmp.c>

#### Integration contract
- Immediate runtime path:
  - `kmain` owns the first release-path helper sanity path until `M6` becomes the natural
    subsystem consumer
  - the release path calls `kfs_strlen` first, then `kfs_strcmp`
  - runtime emits fixed ordered markers:
    - `STRLEN_OK`
    - `STRCMP_OK`
    - `STRING_HELPERS_OK`
  - any failed string-helper self-check emits `STRING_HELPERS_FAIL` and must stop before the later
    normal-flow marker
- Later runtime path:
  - `M6` becomes the first ordinary subsystem consumer
- Ownership rule:
  - `M5.2` may reuse `M4` failure/reporting structure but does not own that structure

#### Acceptance criteria
- The repo implements kernel-owned `strlen` and `strcmp` with the contracts above.
- The final kernel exports `kfs_strlen` and `kfs_strcmp`.
- The release path proves real helper use.
- The feature explicitly rejects hosted fallbacks and volatile/MMIO string semantics.

#### Proof matrix
- `UT-M5.2-1`
  - Assertion:
    - `strlen` returns correct lengths for empty and ordinary strings
  - Evidence:
    - `tests/host_string.rs`
    - `scripts/tests/unit/string-helpers.sh i386 host-strlen-unit-tests-pass`
  - Failure caught:
    - broken loop termination and count logic
  - Status:
    - exists now
- `UT-M5.2-2`
  - Assertion:
    - `strcmp` returns correct sign behavior for equality and ordinary ordering
  - Evidence:
    - `tests/host_string.rs`
    - `scripts/tests/unit/string-helpers.sh i386 host-strcmp-unit-tests-pass`
  - Failure caught:
    - wrong comparison sign for common cases
  - Status:
    - exists now
- `UT-M5.2-3`
  - Assertion:
    - `strlen` stops at the first NUL and `strcmp` behaves correctly on high-byte cases
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 host-strlen-embedded-nul-stops-first`
    - `scripts/tests/unit/string-helpers.sh i386 host-strcmp-high-byte-ordering`
  - Failure caught:
    - scanning past first NUL and signed-byte ordering mistakes
  - Status:
    - to add
- `WP-M5.2-4`
  - Assertion:
    - the repo defines the raw string helper functions in the kernel
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 rust-defines-strlen`
    - `scripts/tests/unit/string-helpers.sh i386 rust-defines-strcmp`
  - Failure caught:
    - helpers only existing as external fallbacks
  - Status:
    - exists now
- `WP-M5.2-5`
  - Assertion:
    - the repo exports `kfs_strlen` and `kfs_strcmp`
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 rust-exports-kfs-strlen`
    - `scripts/tests/unit/string-helpers.sh i386 rust-exports-kfs-strcmp`
  - Failure caught:
    - no real low-level helper ABI despite the feature claiming one
  - Status:
    - to add
- `WP-M5.2-6`
  - Assertion:
    - no hosted fallback is used
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 rust-avoids-extern-strlen`
    - `scripts/tests/unit/string-helpers.sh i386 rust-avoids-extern-strcmp`
  - Failure caught:
    - hidden host-library dependence
  - Status:
    - exists now
- `WP-M5.2-7`
  - Assertion:
    - the release kernel exports the real helper ABI
  - Evidence:
    - `scripts/tests/unit/string-helpers.sh i386 release-kernel-exports-kfs-strlen`
    - `scripts/tests/unit/string-helpers.sh i386 release-kernel-exports-kfs-strcmp`
  - Failure caught:
    - wrappers defined in source but absent from the artifact
  - Status:
    - to add
- `SM-M5.2-8`
  - Assertion:
    - the release path reaches `kfs_strlen` and `kfs_strcmp`
  - Evidence:
    - `scripts/boot-tests/string-runtime.sh i386 release-kmain-calls-kfs-strlen`
    - `scripts/boot-tests/string-runtime.sh i386 release-kmain-calls-kfs-strcmp`
    - `scripts/boot-tests/string-runtime.sh i386 runtime-confirms-string-helpers`
  - Failure caught:
    - helpers linked but dead in the running kernel
  - Status:
    - to add
- `AT-M5.2-9`
  - Assertion:
    - runtime markers stay ordered as `STRLEN_OK -> STRCMP_OK -> STRING_HELPERS_OK` and the
      implementation stays free of volatile ordinary-memory reads
  - Evidence:
    - `scripts/boot-tests/string-runtime.sh i386 runtime-string-markers-are-ordered`
    - `scripts/tests/unit/string-helpers.sh i386 string-helpers-avoid-volatile-reads`
  - Failure caught:
    - fake integration proof and wrong memory model for ordinary strings
  - Status:
    - to add
- `RT-M5.2-10`
  - Assertion:
    - broken string-helper integration emits `STRING_HELPERS_FAIL` and stops the later normal flow
  - Evidence:
    - `scripts/rejection-tests/string-rejections.sh i386 bad-string-self-check-fails`
    - `scripts/rejection-tests/string-rejections.sh i386 bad-string-stops-before-normal-flow`
  - Failure caught:
    - kernel silently continuing after a foundational helper failure
  - Status:
    - to add

#### Common bad implementations
- scanning past the first NUL and still passing trivial strings
- wrong sign behavior for prefix or high-byte cases
- wrappers absent from the release artifact
- helpers reachable only in tests
- volatile ordinary-memory reads

#### Explicit exclusions
- `M5.2` does not promise null-pointer handling.
- `M5.2` does not promise unterminated-buffer recovery.
- `M5.2` does not define user-buffer safety.
- `M5.2` does not define UTF-8 or text-format semantics.

#### Source basis
- `docs/subject.pdf`
- OSDev Rust: <https://wiki.osdev.org/Rust>
- OSDev Sysroot: <https://wiki.osdev.org/Sysroot>
- OSDev C Library: <https://wiki.osdev.org/C_Library>
- Linux From Scratch book: <https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/LFS-BOOK-13.0-NOCHUNKS.html>

### Feature M5.3: Derived memory helper family (`memcpy`, `memset`)

#### Subject basis
- The subject does not name `memcpy` and `memset` explicitly.
- The subject does require a basic kernel library, and later screen/buffer work naturally depends on
  byte-copy and byte-fill primitives.
- Therefore `M5.3` is repo-derived scaling scope, not a literal quoted subject item.

#### Current repo truth
- Status: missing now
  - `src/kernel/memory.rs`
  - `src/kernel/memory/memory_impl.rs`
  - `tests/host_memory.rs`
  - `scripts/tests/unit/memory-helpers.sh`
  - `scripts/boot-tests/memory-runtime.sh`
  - `scripts/rejection-tests/memory-rejections.sh`
  - any memory-helper runtime integration

#### Target end-state
- Status: build now
  - `src/kernel/memory.rs`
  - `src/kernel/memory/memory_impl.rs`
  - `tests/host_memory.rs`
  - `scripts/tests/unit/memory-helpers.sh`
  - `scripts/boot-tests/memory-runtime.sh`
  - `scripts/rejection-tests/memory-rejections.sh`
  - `kfs_memcpy`
  - `kfs_memset`
  - one `kmain`-owned runtime sanity path until a more natural buffer consumer exists
- Status: define now, integrate later
  - `M6` or the first real buffer consumer as the natural subsystem user
- Status: future only
  - `memmove`
  - allocator-backed buffer abstractions
  - MMIO/device-memory copy semantics

#### Intent
- Add the next foundational helper family so later screen and buffer work does not smuggle in hosted
  assumptions.
- Keep the contract narrow and honest: valid ordinary RAM buffers only.
- Reuse the `M5.1` helper-family architecture and low-level ABI conventions without redefining them per helper.

#### Architecture decision
- Decision:
  - `M5.3` must reuse the `M5.1` helper-family architecture and low-level ABI conventions unchanged
  - Why:
    - the second concrete helper family should prove that the `M5.1` scaffold is the permanent kernel-library pattern, not a string-only exception
  - Source:
    - `M5.1` in this repo
    - repo-derived architecture ownership rule
  - Immediate consumer:
    - memory helper family
  - Future consumer:
    - later helper families
- Decision:
  - use the same family structure as `M5.2`:
    - public family file
    - exported ABI wrappers
    - private leaf implementation file
  - Why:
    - helper families should share one architectural pattern
  - Source:
    - repo-derived from `M5.1` plus OSDev Sysroot / C Library
  - Immediate consumer:
    - `kmain`-owned runtime sanity path
  - Future consumer:
    - screen/buffer code
- Decision:
  - use plain byte loops first
  - Why:
    - correctness and proofability matter more than premature optimization here
  - Source:
    - repo-derived from early-kernel stage constraints
  - Immediate consumer:
    - host/unit proof
  - Future consumer:
    - later optimized versions if ever justified
- Decision:
  - treat `memcpy` as non-overlap-safe and do not smuggle `memmove` semantics into it
  - Why:
    - the helper contract must stay honest and minimal
  - Source:
    - OSDev C Library
    - repo-derived helper-boundary discipline
  - Immediate consumer:
    - host/unit proof
  - Future consumer:
    - later buffer-management code

#### Implementation contract
- Build now:
  - reuse the `M5.1` family pattern unchanged:
    - public family file: `src/kernel/memory.rs`
    - private leaf file: `src/kernel/memory/memory_impl.rs`
    - exported low-level wrappers follow the `M5.1` ABI rules
    - other kernel code must not import `src/kernel/memory/memory_impl.rs` directly
  - `src/kernel/memory/memory_impl.rs`
    - `memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
    - `memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`
  - `src/kernel/memory.rs`
    - public Rust family API
    - `kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
    - `kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`
  - `tests/host_memory.rs`
  - `scripts/tests/unit/memory-helpers.sh`
  - `scripts/boot-tests/memory-runtime.sh`
  - `scripts/rejection-tests/memory-rejections.sh`
  - one `kmain`-owned runtime sanity path until a more natural buffer consumer exists
- Define now, integrate later:
  - `M6` and later buffer consumers as the first natural subsystem users
- Future only:
  - `memmove` and richer buffer abstractions

#### Data / ABI conventions
- `memcpy`
  - inputs: valid non-overlapping ordinary RAM buffers plus `len`
  - output: original destination pointer
- `memset`
  - inputs: valid ordinary RAM buffer, fill byte, and `len`
  - output: original destination pointer
- Zero-length operations are valid and must not write outside the requested range.
- Out of contract:
  - overlap-safe movement beyond real `memcpy`
  - invalid-pointer recovery
  - MMIO/device semantics
  - allocator behavior
- Required exported wrapper signatures:
  - `kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
  - `kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`

#### Sub-spec M5.3.a: `memcpy`

##### Subject basis
- The subject does not name `memcpy` explicitly.
- Repo-derived choice:
  - once the kernel owns its helper library, a byte-copy primitive is the next foundational helper for
    later screen and buffer work
  - `memcpy` is therefore part of the repo’s scaling contract, not a literal quoted subject item

##### Current repo truth
- Status: missing now
  - raw `memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
  - `kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
  - `tests/host_memory.rs`
  - `scripts/tests/unit/memory-helpers.sh`
  - `scripts/boot-tests/memory-runtime.sh`
  - `scripts/rejection-tests/memory-rejections.sh`
  - any runtime path that reaches `kfs_memcpy`

##### Target end-state
- Status: build now
  - raw leaf `memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
  - exported wrapper `kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
  - host proofs for ordinary copy, zero-length, return-pointer behavior, and sentinel-preserving bounds
  - source/build proofs for wrapper export and release-kernel symbol export
  - runtime proof that the release path reaches `kfs_memcpy` before `kfs_memset`
- Status: define now, integrate later
  - later internal optimization that preserves the same ABI and proof surface
- Status: future only
  - overlap-safe movement
  - arch-specific assembly fast paths
  - MMIO/device-memory copy helpers

##### Intent
- Define the kernel’s first ordinary-RAM byte-copy primitive.
- Keep the contract narrow and honest: valid non-overlapping ranges only.
- Reuse the `M5.1` family scaffold and low-level ABI rules exactly as the `memcpy` ownership
  boundary.

##### Architecture decision
- Decision:
  - keep `memcpy` behind the memory-family public API and exported wrapper
  - Why:
    - callers should depend on the family surface and `kfs_` ABI, not on the leaf implementation
      directly
  - Source:
    - `M5.1` architecture in this repo
    - OSDev C Library
  - Immediate consumer:
    - `kmain` memory sanity path
  - Future consumer:
    - `M6` buffer/screen code
- Decision:
  - use a plain byte loop as the required completion baseline
  - Why:
    - early-kernel correctness and proofability matter more than premature micro-optimization
  - Source:
    - repo-derived early-kernel constraint
  - Immediate consumer:
    - unit and runtime proofs
  - Future consumer:
    - later optimized internal implementation
- Decision:
  - keep overlap handling out of `memcpy`
  - Why:
    - fake `memmove` semantics would blur the contract and weaken later memory-helper boundaries
  - Source:
    - OSDev C Library
    - repo-derived helper-boundary discipline
  - Immediate consumer:
    - host proof cases
  - Future consumer:
    - later explicit `memmove` ownership if added

##### Implementation contract
- Build now:
  - reuse the `M5.1` helper boundary:
    - public family entry stays in `src/kernel/memory.rs`
    - leaf algorithm stays in `src/kernel/memory/memory_impl.rs`
    - exported low-level wrapper follows the `M5.1` ABI rules for primitive-only signatures
  - raw leaf: `memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
  - wrapper/export: `kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`
  - host cases for:
    - ordinary non-overlapping copy
    - zero-length copy
    - destination-pointer return behavior
    - sentinel-preserving bounds around the target range
  - source/build checks for:
    - wrapper export
    - release-kernel symbol export
    - no volatile ordinary-RAM reads or writes
- Define now, integrate later:
  - later internal optimization hidden behind the same wrapper and proof surface
- Future only:
  - overlap-safe movement

##### Data / ABI conventions
- Inputs:
  - destination pointer to valid writable ordinary RAM
  - source pointer to valid readable ordinary RAM
  - `len` byte count
- Output:
  - original destination pointer
- Required behavioral rules:
  - copy exactly `len` bytes
  - preserve bytes outside the requested range
  - zero-length copy must not write outside the requested range
- Internal implementation rules:
  - ordinary reads and writes only
  - no volatile semantics for ordinary RAM buffers
  - overlap is out of contract and must not be smuggled in as hidden `memmove`

##### Runtime / integration path
- `kmain` is the first runtime owner of the `memcpy` sanity path.
- The release runtime path must call `kfs_memcpy` before `kfs_memset`.
- The runtime proof must expose `MEMCPY_OK` before the later memory-family success marker.

##### Acceptance criteria
- The repo exports `kfs_memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8`.
- `memcpy` copies exactly the requested byte range for valid non-overlapping ordinary-RAM buffers.
- Zero-length behavior and destination-pointer return behavior are covered by proof.
- The running kernel proves that `kfs_memcpy` is reached in the real release path.

##### Proof matrix
- `UT-M5.3.a-1`
  - Assertion:
    - `memcpy` copies bytes correctly on ordinary non-overlapping ranges
  - Evidence:
    - `tests/host_memory.rs`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memcpy-unit-tests-pass`
  - Failure caught:
    - wrong copy direction or wrong byte count
  - Status:
    - to add
- `UT-M5.3.a-2`
  - Assertion:
    - zero-length copy and destination-pointer return behavior are correct
  - Evidence:
    - `scripts/tests/unit/memory-helpers.sh i386 host-memcpy-zero-length-behavior`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memcpy-return-pointer-behavior`
  - Failure caught:
    - off-by-one writes and wrong public contract
  - Status:
    - to add
- `AT-M5.3.a-3`
  - Assertion:
    - sentinel tests catch writes outside the requested range
  - Evidence:
    - `scripts/tests/unit/memory-helpers.sh i386 host-memcpy-sentinel-bounds`
  - Failure caught:
    - out-of-range writes hidden by naive happy-path tests
  - Status:
    - to add
- `WP-M5.3.a-4`
  - Assertion:
    - the repo exports `kfs_memcpy` in source and in the release kernel artifact
  - Evidence:
    - `scripts/tests/unit/memory-helpers.sh i386 rust-exports-kfs-memcpy`
    - `scripts/tests/unit/memory-helpers.sh i386 release-kernel-exports-kfs-memcpy`
  - Failure caught:
    - helper logic existing only as an internal function with no stable low-level ABI
  - Status:
    - to add
- `SM-M5.3.a-5`
  - Assertion:
    - the release runtime path reaches `kfs_memcpy` and emits `MEMCPY_OK`
  - Evidence:
    - `scripts/boot-tests/memory-runtime.sh i386 release-kmain-calls-kfs-memcpy`
    - `scripts/boot-tests/memory-runtime.sh i386 runtime-confirms-memcpy`
  - Failure caught:
    - linked helper code that is never executed by the running kernel
  - Status:
    - to add
- `RT-M5.3.a-6`
  - Assertion:
    - a broken `memcpy` self-check emits `MEMORY_HELPERS_FAIL` and stops later normal flow
  - Evidence:
    - `scripts/rejection-tests/memory-rejections.sh i386 bad-memory-self-check-fails`
  - Failure caught:
    - kernel continuing after a foundational memory-copy mismatch
  - Status:
    - to add

##### Common bad implementations
- writing one byte too many at the end of the range
- returning the wrong pointer value
- silently treating overlap as supported behavior
- using volatile ordinary-RAM semantics

##### Explicit exclusions
- `memcpy` does not define overlap-safe movement.
- `memcpy` does not promise invalid-pointer recovery.
- `memcpy` does not define MMIO/device-memory semantics.

##### Source basis
- `docs/subject.pdf`
- OSDev C Library: <https://wiki.osdev.org/C_Library>
- OSDev Sysroot: <https://wiki.osdev.org/Sysroot>
- OSDev Why do I need a Cross Compiler?: <https://wiki.osdev.org/Why_do_I_need_a_Cross_Compiler>

#### Sub-spec M5.3.b: `memset`

##### Subject basis
- The subject does not name `memset` explicitly.
- Repo-derived choice:
  - once the kernel owns its helper library, a byte-fill primitive is the next foundational helper for
    later screen and buffer initialization work
  - `memset` is therefore part of the repo’s scaling contract, not a literal quoted subject item

##### Current repo truth
- Status: missing now
  - raw `memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`
  - `kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`
  - `tests/host_memory.rs`
  - `scripts/tests/unit/memory-helpers.sh`
  - `scripts/boot-tests/memory-runtime.sh`
  - `scripts/rejection-tests/memory-rejections.sh`
  - any runtime path that reaches `kfs_memset`

##### Target end-state
- Status: build now
  - raw leaf `memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`
  - exported wrapper `kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`
  - host proofs for ordinary fill, zero-length, return-pointer behavior, and sentinel-preserving bounds
  - source/build proofs for wrapper export and release-kernel symbol export
  - runtime proof that the release path reaches `kfs_memset` after `kfs_memcpy`
- Status: define now, integrate later
  - later internal optimization that preserves the same ABI and proof surface
- Status: future only
  - MMIO/device-memory fill helpers
  - wider architecture-specific fill paths

##### Intent
- Define the kernel’s first ordinary-RAM byte-fill primitive.
- Keep the contract narrow and honest: valid writable ordinary RAM only.
- Reuse the `M5.1` family scaffold and low-level ABI rules exactly as the `memset` ownership
  boundary.

##### Architecture decision
- Decision:
  - keep `memset` behind the memory-family public API and exported wrapper
  - Why:
    - callers should depend on the family surface and `kfs_` ABI, not on the leaf implementation
      directly
  - Source:
    - `M5.1` architecture in this repo
    - OSDev C Library
  - Immediate consumer:
    - `kmain` memory sanity path
  - Future consumer:
    - `M6` buffer/screen initialization paths
- Decision:
  - use a plain byte loop as the required completion baseline
  - Why:
    - the first requirement is visible correctness on ordinary RAM buffers
  - Source:
    - repo-derived early-kernel constraint
  - Immediate consumer:
    - unit and runtime proofs
  - Future consumer:
    - later optimized internal implementation
- Decision:
  - keep the fill-byte contract explicit and scalar
  - Why:
    - callers need byte fill semantics, not hidden typed or wider-word fill semantics
  - Source:
    - OSDev C Library
    - repo-derived helper-boundary discipline
  - Immediate consumer:
    - host proof cases
  - Future consumer:
    - later screen/buffer initialization code

##### Implementation contract
- Build now:
  - reuse the `M5.1` helper boundary:
    - public family entry stays in `src/kernel/memory.rs`
    - leaf algorithm stays in `src/kernel/memory/memory_impl.rs`
    - exported low-level wrapper follows the `M5.1` ABI rules for primitive-only signatures
  - raw leaf: `memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`
  - wrapper/export: `kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`
  - host cases for:
    - ordinary fill
    - zero-length fill
    - destination-pointer return behavior
    - sentinel-preserving bounds around the target range
    - non-zero fill-byte cases
  - source/build checks for:
    - wrapper export
    - release-kernel symbol export
    - no volatile ordinary-RAM writes
- Define now, integrate later:
  - later internal optimization hidden behind the same wrapper and proof surface
- Future only:
  - wider architecture-specific fill paths

##### Data / ABI conventions
- Inputs:
  - destination pointer to valid writable ordinary RAM
  - fill byte value
  - `len` byte count
- Output:
  - original destination pointer
- Required behavioral rules:
  - write exactly `len` bytes of the requested byte value
  - preserve bytes outside the requested range
  - zero-length fill must not write outside the requested range
- Internal implementation rules:
  - ordinary writes only
  - no volatile semantics for ordinary RAM buffers
  - fill behavior is byte-oriented, not typed-object initialization

##### Runtime / integration path
- `kmain` is the first runtime owner of the `memset` sanity path.
- The release runtime path must call `kfs_memset` after `kfs_memcpy`.
- The runtime proof must expose `MEMSET_OK` before the later memory-family success marker.

##### Acceptance criteria
- The repo exports `kfs_memset(dst: *mut u8, value: u8, len: usize) -> *mut u8`.
- `memset` writes exactly the requested byte range for valid ordinary-RAM buffers.
- Zero-length behavior, non-zero fill-byte behavior, and destination-pointer return behavior are
  covered by proof.
- The running kernel proves that `kfs_memset` is reached in the real release path.

##### Proof matrix
- `UT-M5.3.b-1`
  - Assertion:
    - `memset` fills bytes correctly for zero and non-zero byte values
  - Evidence:
    - `tests/host_memory.rs`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memset-unit-tests-pass`
  - Failure caught:
    - wrong fill value or incomplete range coverage
  - Status:
    - to add
- `UT-M5.3.b-2`
  - Assertion:
    - zero-length fill and destination-pointer return behavior are correct
  - Evidence:
    - `scripts/tests/unit/memory-helpers.sh i386 host-memset-zero-length-behavior`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memset-return-pointer-behavior`
  - Failure caught:
    - off-by-one writes and wrong public contract
  - Status:
    - to add
- `AT-M5.3.b-3`
  - Assertion:
    - sentinel tests catch writes outside the requested range
  - Evidence:
    - `scripts/tests/unit/memory-helpers.sh i386 host-memset-sentinel-bounds`
  - Failure caught:
    - out-of-range writes hidden by naive happy-path tests
  - Status:
    - to add
- `WP-M5.3.b-4`
  - Assertion:
    - the repo exports `kfs_memset` in source and in the release kernel artifact
  - Evidence:
    - `scripts/tests/unit/memory-helpers.sh i386 rust-exports-kfs-memset`
    - `scripts/tests/unit/memory-helpers.sh i386 release-kernel-exports-kfs-memset`
  - Failure caught:
    - helper logic existing only as an internal function with no stable low-level ABI
  - Status:
    - to add
- `SM-M5.3.b-5`
  - Assertion:
    - the release runtime path reaches `kfs_memset` and emits `MEMSET_OK`
  - Evidence:
    - `scripts/boot-tests/memory-runtime.sh i386 release-kmain-calls-kfs-memset`
    - `scripts/boot-tests/memory-runtime.sh i386 runtime-confirms-memset`
  - Failure caught:
    - linked helper code that is never executed by the running kernel
  - Status:
    - to add
- `RT-M5.3.b-6`
  - Assertion:
    - a broken `memset` self-check emits `MEMORY_HELPERS_FAIL` and stops later normal flow
  - Evidence:
    - `scripts/rejection-tests/memory-rejections.sh i386 bad-memory-self-check-fails`
  - Failure caught:
    - kernel continuing after a foundational memory-fill mismatch
  - Status:
    - to add

##### Common bad implementations
- writing one byte too many at the end of the range
- returning the wrong pointer value
- filling with the wrong byte value on non-zero cases
- using volatile ordinary-RAM semantics

##### Explicit exclusions
- `memset` does not promise invalid-pointer recovery.
- `memset` does not define MMIO/device-memory semantics.
- `memset` does not define typed-object initialization semantics.

##### Source basis
- `docs/subject.pdf`
- OSDev C Library: <https://wiki.osdev.org/C_Library>
- OSDev Sysroot: <https://wiki.osdev.org/Sysroot>
- OSDev Why do I need a Cross Compiler?: <https://wiki.osdev.org/Why_do_I_need_a_Cross_Compiler>

#### Integration contract
- Immediate runtime path:
  - until a natural buffer consumer exists, `kmain` owns one fixed runtime sanity path
  - that path calls `kfs_memcpy` first, then `kfs_memset`
  - runtime emits fixed ordered markers:
    - `MEMCPY_OK`
    - `MEMSET_OK`
    - `MEMORY_HELPERS_OK`
  - any failed memory-helper self-check emits `MEMORY_HELPERS_FAIL` and must stop before the later
    normal-flow marker
- Later runtime path:
  - `M6` and later buffer-management code become ordinary consumers

#### Acceptance criteria
- The repo implements kernel-owned `memcpy` and `memset` with the contracts above.
- The final kernel exports `kfs_memcpy` and `kfs_memset`.
- Zero-length and sentinel-style edge cases are covered.
- The feature explicitly rejects hosted fallbacks, MMIO semantics, and fake `memmove` behavior.

#### Proof matrix
- `UT-M5.3-1`
  - Assertion:
    - `memcpy` copies bytes correctly on valid non-overlapping ranges
  - Evidence:
    - `tests/host_memory.rs`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memcpy-unit-tests-pass`
  - Failure caught:
    - wrong copy semantics
  - Status:
    - to add
- `UT-M5.3-2`
  - Assertion:
    - `memset` fills bytes correctly
  - Evidence:
    - `tests/host_memory.rs`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memset-unit-tests-pass`
  - Failure caught:
    - wrong fill semantics
  - Status:
    - to add
- `UT-M5.3-3`
  - Assertion:
    - zero-length operations and destination-pointer return behavior are correct
  - Evidence:
    - `tests/host_memory.rs`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memory-zero-length-behavior`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memory-return-pointer-behavior`
  - Failure caught:
    - off-by-one writes and wrong return values
  - Status:
    - to add
- `WP-M5.3-4`
  - Assertion:
    - the repo exports `kfs_memcpy` and `kfs_memset` and avoids hosted fallbacks
  - Evidence:
    - `scripts/tests/unit/memory-helpers.sh i386 rust-exports-kfs-memcpy`
    - `scripts/tests/unit/memory-helpers.sh i386 rust-exports-kfs-memset`
    - `scripts/tests/unit/memory-helpers.sh i386 rust-avoids-extern-memcpy`
    - `scripts/tests/unit/memory-helpers.sh i386 rust-avoids-extern-memset`
  - Failure caught:
    - missing helper ABI or hidden host-library dependence
  - Status:
    - to add
- `SM-M5.3-5`
  - Assertion:
    - the running kernel reaches the memory-helper path
  - Evidence:
    - `scripts/boot-tests/memory-runtime.sh i386 release-kmain-calls-kfs-memcpy`
    - `scripts/boot-tests/memory-runtime.sh i386 release-kmain-calls-kfs-memset`
    - `scripts/boot-tests/memory-runtime.sh i386 runtime-confirms-memory-helpers`
  - Failure caught:
    - helpers linked but dead in the running kernel
  - Status:
    - to add
- `AT-M5.3-6`
  - Assertion:
    - sentinel tests catch out-of-range writes, runtime markers stay ordered as
      `MEMCPY_OK -> MEMSET_OK -> MEMORY_HELPERS_OK`, and the implementation avoids volatile
      ordinary-RAM semantics
  - Evidence:
    - `scripts/tests/unit/memory-helpers.sh i386 host-memcpy-sentinel-bounds`
    - `scripts/tests/unit/memory-helpers.sh i386 host-memset-sentinel-bounds`
    - `scripts/tests/unit/memory-helpers.sh i386 memory-helpers-avoid-volatile-writes`
    - `scripts/boot-tests/memory-runtime.sh i386 runtime-memory-markers-are-ordered`
  - Failure caught:
    - hidden off-by-one bugs and wrong memory model
  - Status:
    - to add
- `RT-M5.3-7`
  - Assertion:
    - broken memory-helper integration emits `MEMORY_HELPERS_FAIL` and stops the later normal flow
  - Evidence:
    - `scripts/rejection-tests/memory-rejections.sh i386 bad-memory-self-check-fails`
    - `scripts/rejection-tests/memory-rejections.sh i386 bad-memory-stops-before-normal-flow`
  - Failure caught:
    - kernel silently continuing after a foundational memory-helper failure
  - Status:
    - to add

#### Common bad implementations
- treating `memcpy` as overlap-safe `memmove`
- off-by-one writes hidden until sentinel checks exist
- wrong destination-pointer return behavior
- volatile semantics for ordinary RAM helpers
- helpers linked but never executed by the running kernel

#### Explicit exclusions
- `M5.3` does not define `memmove`.
- `M5.3` does not promise invalid-pointer recovery.
- `M5.3` does not define MMIO/device-memory copy semantics.
- `M5.3` does not define allocation or ownership semantics.

#### Source basis
- `docs/subject.pdf`
- OSDev Sysroot: <https://wiki.osdev.org/Sysroot>
- OSDev C Library: <https://wiki.osdev.org/C_Library>
- OSDev Why do I need a Cross Compiler?: <https://wiki.osdev.org/Why_do_I_need_a_Cross_Compiler>
- Linux From Scratch book: <https://www.linuxfromscratch.org/lfs/downloads/stable-systemd/LFS-BOOK-13.0-NOCHUNKS.html>

### Definition of Done (M5)
- `M5.1` defines and builds the helper scaffold, immediate semantic types, and ABI/data conventions.
- `M5.2` builds the subject-explicit string family with meaningful `UT/WP/SM/AT/RT` coverage.
- `M5.3` either builds the derived memory family to the same standard or remains the only explicitly
  named incomplete part of the epic.
- `M5` is not considered complete if current repo truth and target end-state are blurred together.
- `M5` is not considered complete if proof items are listed without failure modes or status.

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
Intent:
- Wire the build so all kernel objects are linked into the final kernel binary using the
  project linker script.
- Keep this feature focused on the **actual link command in the build workflow**, not on
  linker-script contents (M3.1/M3.2) and not on ASM bootstrap behavior (M2).

Implementation tasks:
- Invoke `ld` from the build with `-T src/arch/i386/linker.ld`.
- Use the correct linker mode for i386 (`-m elf_i386`).
- Link ASM and chosen-language objects into one final kernel artifact.

Acceptance criteria:
- The Makefile links the final kernel with the project linker script.
- The link command includes both ASM objects and chosen-language objects.
- The produced kernel artifact boots through the normal GRUB workflow.

Implementation scope:
- `MAKE` + `LD`

Proof / tests (definition of done):
- WP-M7.3-1 (ld uses -m elf_i386 and the project script): `make -n all arch=i386 | rg -n "\\bld\\b" | rg -q "(-m\\s+elf_i386).*\\s-T\\s+src/arch/i386/linker\\.ld"`
- WP-M7.3-2 (link command includes ASM and chosen-language objects): `make -n all arch=i386 | rg -n "build/arch/i386/.*\\.o.*build/arch/i386/rust/.*\\.o|build/arch/i386/rust/.*\\.o.*build/arch/i386/.*\\.o"`
- MANUAL-M7.3-1 (boots): `make run arch=i386` and confirm GRUB loads the kernel and reaches your entry. (Automation: prefer AUTO-M7.3-1)
- AUTO-M7.3-1 (preferred for CI): use **Infra I0.1** as the boot gate; if kernel exits PASS, the link + GRUB load path succeeded

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
