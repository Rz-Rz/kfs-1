# KFS_1 Repo Status vs Subject (Done / Not Done + Priorities)

Snapshot date: March 7, 2026.

This file is an analysis of the current repository state against the backlog in:
- `docs/kfs1_epics_features.md` (baseline spec/backlog)

Scope:
- Focus on **Base (Mandatory)** epics (M0–M8).
- Bonus and repo-extension epics (B1–B6) are listed as deferred (not required right now).

As-of snapshot:
- Kernel artifact present: `build/kernel-i386.bin` (ELF32, Intel 80386)
- ISO artifact present: `build/os-i386.iso` (bootable ISO9660, <= 10 MB)
- Disk-image artifact present: `build/os-i386.img` (bootable ISO9660, <= 10 MB; boots via QEMU `-drive`)
- Sources present in ASM under `src/arch/i386/` and minimal Rust under `src/rust/`
- Chosen language: **Rust** (Rust is compiled/linked into the kernel; `kmain` is implemented and called from ASM in release builds)

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
- Base Epic M2 DoD: ✅ YES (Multiboot header + stack init + handoff to `kmain`)
  - Proof: `make test arch=i386` (builds artifacts and boots them; M4.1 check ensures `kmain` exists and is called in release kernel)
- Base Epic M3 DoD: ✅ YES (custom linker script, standard sections, exported layout symbols)
  - Proof: `make test arch=i386` (includes M3.2 + M3.3 checks)
- Base Epic M4 DoD: ✅ YES (Rust `kmain` exists and is reachable from ASM)
  - Proof: `make test arch=i386` (includes an M4.1 check for `kmain`)
- Base Epic M5 DoD: ✅ YES (kernel helper layer is present with host-tested string+memory helpers)
  - Proof: `make test arch=i386` (includes M5.2 + M5.3 host helper checks)
- Base Epic M6 DoD: ✅ YES (screen interface exists, newline/cursor handling works, and `42` is printed through the VGA module)
  - Proof: `bash scripts/check-m6.1-vga.sh i386`
  - Proof: `bash scripts/check-m6.2-newline.sh i386`
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
Proof:
- `make test arch=i386` (asserts the test kernel includes ASM+Rust symbols, then runs the four “no host libs (ELF checks)” steps)
- `nm -n build/kernel-i386-test.bin | rg -n "\\bkfs_rust_marker\\b"`
- `nm -n build/kernel-i386.bin | rg -n "\\bkfs_rust_marker\\b"` (release kernel also links Rust)
- `KFS_M0_2_INCLUDE_RELEASE=1 bash scripts/check-m0.2-freestanding.sh i386 all` (checks both test + release kernels)

### Feature M0.3: Size discipline baked into workflow
Status: ✅ Mostly done (image size)
Evidence:
- `build/os-i386.iso` is <= 10 MB
Proof:
- `ISO=build/os-i386.iso; test $(wc -c < "$ISO") -le 10485760 && echo "ISO <= 10MB"`

Epic DoD (M0) complete? ✅

Note:
- M0.1 is complete (i386 toolchain + ELF32).
- M0.2 is enforced on a Rust-linked kernel artifact via `make test` (Rust is present but `kmain` is still not implemented).

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
- The linked kernel contains those sections and includes canary symbols in `.rodata` and `.data`
Proof:
- `rg -n "^\\s*\\.(text|rodata|data|bss)\\b" -S src/arch/i386/linker.ld`
- `bash scripts/check-m3.2-sections.sh i386`

### Feature M3.3: Export useful layout symbols
Status: ✅ Done
Evidence:
- Linker script exports `kernel_start`, `kernel_end`, `bss_start`, `bss_end`
- Rust references these layout symbols via an `extern "C"` declaration
Proof:
- `nm -n build/kernel-i386.bin | rg -n "\\b(kernel_start|kernel_end|bss_start|bss_end)\\b"`
- `rg -n "extern\\s+\"C\"\\s*\\{|\\b(kernel_start|kernel_end|bss_start|bss_end)\\b" -S src/rust/layout_symbols.rs`
- `bash scripts/check-m3.3-layout-symbols.sh i386`

Epic DoD (M3) complete? ✅

---

## Base Epic M4: Minimal Kernel in Your Chosen Language

Status: ✅ Done
Proof:
- `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "\\bkmain\\b"`
- `KERNEL=build/kernel-i386.bin; objdump -d "$KERNEL" | rg -n "call.*<kmain>"`
- `bash scripts/check-m4.1-kmain.sh i386`

---

## Base Epic M5: Basic Kernel Library (Helpers)

Status: ✅ Done (M5.2 + M5.3 implemented; native Rust types policy kept)
Evidence:
- Rust string helpers are implemented in `src/kernel/string/string_impl.rs` (module included by `src/kernel/string.rs`) (`strlen`, `strcmp`)
- Rust memory helpers are implemented in `src/kernel/memory/memory_impl.rs` (module included by `src/kernel/memory.rs`) (`memcpy`, `memset`)
- Host unit tests exist in `tests/host_string.rs` and are enforced by `scripts/check-m5.2-string.sh`
- Host unit tests exist in `tests/host_mem.rs` and are enforced by `scripts/check-m5.3-memory.sh`
Proof:
- `bash scripts/check-m5.2-string.sh i386`
- `bash scripts/check-m5.3-memory.sh i386`
- `rg -n "\\bfn\\s+(strlen|strcmp)\\b" -S src/kernel`
- `rg -n "\\bfn\\s+(memcpy|memset)\\b" -S src/kernel`

---

## Base Epic M6: Screen I/O Interface + Mandatory Output

### Feature M6.1: VGA text mode writer (VGA memory at `0xB8000`)
Status: ✅ Done
Evidence:
- Reusable VGA writer API exists in `src/kernel/vga.rs` (`vga_init`, `vga_putc`, `vga_puts`)
- `kmain` uses the VGA module instead of writing directly to `0xB8000`
Proof:
- `rg -n "\\bvga_(init|putc|puts)\\b" -S src/kernel`
- `KERNEL=build/kernel-i386.bin; nm -n "$KERNEL" | rg -n "\\b(vga_init|vga_putc|vga_puts)\\b"`
- `bash scripts/check-m6.1-vga.sh i386`

### Feature M6.2: Newline handling (basic cursor movement)
Status: ✅ Done
Evidence:
- `src/kernel/vga.rs` now tracks cursor state through the shared `VgaCursor` implementation in `src/kernel/vga/vga_impl.rs`
- `vga_putc` treats `\n` as cursor movement, and `kmain` exercises the newline path through VGA output calls
- Host unit coverage exists in `tests/host_cursor.rs`
Proof:
- `bash scripts/check-m6.2-newline.sh i386`
- `rg -n "\\b(VgaCursor|row|col)\\b|\\\\n" -S src/kernel tests/host_cursor.rs`

### Feature M6.3: Mandatory output: display `42`
Status: ✅ Done (printed via VGA module from `kmain`)
Evidence:
- `kmain` calls `vga_init` + `vga_puts("42")`
Proof:
- `rg -n "\\bvga_(init|puts)\\b|42" -S src/kernel/kmain.rs`
- `rg -n "\\b42\\b|\\\"42\\\"" -S src || echo "no 42 yet"`

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

## Infra Epics Status (I0–I3)

Status: ⚠️ Partial
Evidence:
- Infra Epic **I0** (Deterministic QEMU PASS/FAIL): ✅ Done
  - Proof: `make test arch=i386` exits deterministically (PASS) and never hangs
  - Proof: `make test arch=i386 KFS_TEST_FORCE_FAIL=1` fails deterministically
- Infra Epic **I3** (Reproducible Dev Environment): ✅ Done
  - Proof: `make container-env-check`
- Infra Epic **I1** (Serial console assertions): ❌ Not done
- Infra Epic **I2** (VGA memory assertions): ❌ Not done

---

## Deferred Bonus / Extension Status (B1–B6)

These items are not required for the base KFS_1 subject, but they are now tracked
explicitly because they match the intended roadmap for the repo.

High-level status:
- Bonus Epic B1 (scroll + cursor support): ⚠️ Partial
- Bonus Epic B2 (color support in the screen I/O interface): ⚠️ Partial
- Bonus Epic B3 (`printk` / formatted printing): ❌ Not started
- Bonus Epic B4 (keyboard input + echo): ❌ Not started
- Bonus Epic B5 (multiple screens + keyboard shortcuts): ❌ Not started
- Bonus Epic B6 (screen geometry / different screen sizes): ❌ Not started

### Bonus Epic B1: Scroll + Cursor Support

Status: ⚠️ Partial
Evidence:
- Cursor state exists in `src/kernel/vga/vga_impl.rs` via `VgaCursor { row, col }`
- Host cursor tests exist in `tests/host_cursor.rs`
- Bottom-of-screen behavior still wraps back to the top; no scroll operation exists yet
- No hardware cursor programming path is present
Proof:
- `bash scripts/check-m6.2-newline.sh i386`
- `rg -n "\\b(VgaCursor|row|col)\\b" -S src/kernel/vga.rs src/kernel/vga/vga_impl.rs tests/host_cursor.rs`
- `rg -n "\\bscroll\\b|0x3D4|0x3D5|outb|inb" -S src tests || echo "no scroll or hardware cursor support yet"`

### Feature B1.1: Maintain cursor state
Status: ✅ Done
Evidence:
- `VgaCursor` tracks `row` and `col` in `src/kernel/vga/vga_impl.rs`
- `vga_putc` advances the saved cursor state and host tests validate cursor math
Proof:
- `bash scripts/check-m6.2-newline.sh i386`
- `rg -n "\\bstruct VgaCursor\\b|\\brow\\b|\\bcol\\b" -S src/kernel/vga/vga_impl.rs tests/host_cursor.rs`

### Feature B1.2: Implement scrolling at bottom-of-screen
Status: ❌ Not done
Evidence:
- `advance_row()` in `src/kernel/vga/vga_impl.rs` wraps to row `0` once `VGA_HEIGHT` is reached
- No line-copy / clear-last-line scroll routine exists in the VGA writer
Proof:
- `rg -n "wraps back to the top instead of scrolling|row >= VGA_HEIGHT|row = 0" -S src/kernel/vga/vga_impl.rs`
- `rg -n "\\bscroll\\b|copy.*line|clear.*last line" -S src/kernel tests || echo "no scroll implementation yet"`

### Feature B1.3: Optional hardware cursor programming (VGA ports `0x3D4/0x3D5`)
Status: ❌ Not done
Evidence:
- No port I/O helpers or hardware cursor register writes are present
Proof:
- `rg -n "0x3D4|0x3D5|outb|inb|hardware cursor" -S src tests || echo "no hardware cursor support yet"`

Definition of Done (B1):
- ❌ Not met: basic cursor state exists, but scrolling and optional hardware cursor support are still missing.

---

### Bonus Epic B2: Color Support in the Screen I/O Interface

Status: ⚠️ Partial
Evidence:
- The writer uses a fixed attribute constant `VGA_COLOR_LIGHT_GREEN_ON_BLACK` in `src/kernel/vga.rs`
- There is no public color API, no color state beyond the fixed constant, and no color-focused tests
Proof:
- `rg -n "VGA_COLOR_LIGHT_GREEN_ON_BLACK|attribute|color" -S src/kernel/vga.rs`
- `rg -n "set_color|write_colored|host_color|foreground|background" -S src tests || echo "no configurable color support yet"`

### Feature B2.1: VGA attribute/color model
Status: ⚠️ Partial
Evidence:
- One hard-coded VGA attribute constant exists
- No reusable foreground/background model or encoding test suite exists yet
Proof:
- `rg -n "VGA_COLOR_LIGHT_GREEN_ON_BLACK" -S src/kernel/vga.rs`
- `rg -n "enum .*Color|const .*COLOR|host_color|attribute encoding" -S src tests || echo "no color model/test coverage yet"`

### Feature B2.2: Screen API to set color per-print or per-screen
Status: ❌ Not done
Evidence:
- The exported VGA API only exposes `vga_init`, `vga_putc`, and `vga_puts`
- Callers cannot change foreground/background color through the screen interface
Proof:
- `rg -n "\\bvga_(init|putc|puts)\\b" -S src/kernel/vga.rs`
- `rg -n "set_color|write_colored|with_color|foreground|background" -S src/kernel tests || echo "no color API yet"`

Definition of Done (B2):
- ❌ Not met: the repo has a fixed color constant, but not configurable color support through the I/O interface.

---

### Bonus Epic B3: `printk` / Formatted Printing

Status: ❌ Not started
Evidence:
- No formatter implementation or `printk`-style wrapper is present
Proof:
- `rg -n "\\bprintk\\b|\\bprintf\\b|format engine|%[scdux%]" -S src tests || echo "no formatted printing yet"`

### Feature B3.1: Minimal format engine (`%s %c %d %u %x %%`)
Status: ❌ Not done
Evidence:
- No formatter module or host formatter tests exist
Proof:
- `rg -n "\\bformat\\b|\\bformatter\\b|host_format|%[scdux%]" -S src tests || echo "no format engine yet"`

### Feature B3.2: `printk` wrapper that prints to screen
Status: ❌ Not done
Evidence:
- No `printk`-style API exists in the kernel sources
Proof:
- `rg -n "\\bprintk\\b|\\bprint_\\w+\\b" -S src tests || echo "no printk wrapper yet"`

Definition of Done (B3):
- ❌ Not met: no formatted printing support is implemented.

---

### Bonus Epic B4: Keyboard Input + Echo

Status: ❌ Not started
Evidence:
- No PS/2 keyboard read path, scancode mapping, or keyboard echo integration exists in `src/`
- No keyboard-focused host tests or runtime checks exist
Proof:
- `rg -n "keyboard|scancode|ps/2|0x60|0x64|backspace|sendkey" -S src tests scripts || echo "no keyboard support yet"`

### Feature B4.1: Read scancodes (polled or IRQ-driven)
Status: ❌ Not done
Evidence:
- No PS/2 controller port access or scancode capture path exists
Proof:
- `rg -n "0x60|0x64|scancode|keyboard|irq1|PS/2|ps2" -S src tests || echo "no scancode reader yet"`

### Feature B4.2: Translate scancodes to key events / printable bytes
Status: ❌ Not done
Evidence:
- No scancode translation tables or key-event abstractions exist
Proof:
- `rg -n "scancode.*ascii|key event|KeyEvent|KeyCode|host_scancode" -S src tests || echo "no scancode translation yet"`

### Feature B4.3: Echo typed characters through the screen I/O interface
Status: ❌ Not done
Evidence:
- No code path routes keyboard input into `vga_putc` / `vga_puts`
- No backspace-handling or keyboard echo tests exist
Proof:
- `rg -n "backspace|echo typed|keyboard.*vga|vga_putc\\(" -S src tests || echo "no keyboard echo integration yet"`

### Feature B4.4: Reserve shortcut keys from the text-echo path
Status: ❌ Not done
Evidence:
- No keyboard event router or shortcut interception exists
Proof:
- `rg -n "shortcut|Alt|Fn|modifier|key handler|terminal switch" -S src tests || echo "no shortcut routing yet"`

Definition of Done (B4):
- ❌ Not met: there is no keyboard input stack in the repo yet.

---

### Bonus Epic B5: Multiple Screens + Keyboard Shortcuts

Status: ❌ Not started
Evidence:
- No per-terminal buffers, active-terminal state, or terminal switch shortcuts exist
Proof:
- `rg -n "virtual terminal|terminal buffer|active terminal|Alt\\+Fn|switch terminal|host_vt" -S src tests || echo "no multi-terminal support yet"`

### Feature B5.1: N virtual terminal buffers
Status: ❌ Not done
Evidence:
- The VGA writer manages one global cursor and writes directly to the visible VGA buffer
- No off-screen terminal buffer model exists
Proof:
- `rg -n "static mut VGA_CURSOR|VGA_TEXT_BUFFER" -S src/kernel/vga.rs`
- `rg -n "terminal buffer|virtual terminal|host_vt" -S src tests || echo "no virtual terminal buffers yet"`

### Feature B5.2: Keyboard shortcuts to switch the active terminal
Status: ❌ Not done
Evidence:
- No active-terminal selector or shortcut-handling path exists
Proof:
- `rg -n "active terminal|switch.*terminal|Alt|Fn|shortcut" -S src tests || echo "no terminal switching shortcuts yet"`

### Feature B5.3: Persist output per terminal across switches
Status: ❌ Not done
Evidence:
- No inactive terminal state is preserved because only the live VGA buffer is written
Proof:
- `rg -n "flush.*VGA|restore.*terminal|preserve.*buffer" -S src tests || echo "no per-terminal restore support yet"`

Definition of Done (B5):
- ❌ Not met: no multiple-screen or shortcut-based terminal switching support exists.

---

### Bonus Epic B6: Screen Geometry / Different Screen Sizes

Status: ❌ Not started
Evidence:
- Screen dimensions are hard-coded as `VGA_WIDTH = 80` and `VGA_HEIGHT = 25`
- No geometry abstraction, alternate preset, or geometry-aware tests exist
Proof:
- `rg -n "VGA_WIDTH|VGA_HEIGHT|80|25" -S src/kernel/vga.rs src/kernel/vga/vga_impl.rs`
- `rg -n "ScreenGeometry|GEOMETRY|host_geometry|preset" -S src tests || echo "no geometry abstraction yet"`

### Feature B6.1: Introduce a geometry abstraction for the screen layer
Status: ❌ Not done
Evidence:
- Cursor math still depends directly on `VGA_WIDTH` / `VGA_HEIGHT`
Proof:
- `rg -n "VGA_WIDTH|VGA_HEIGHT" -S src/kernel/vga/vga_impl.rs src/kernel/vga.rs`

### Feature B6.2: Make wrapping, clearing, and scrolling geometry-aware
Status: ❌ Not done
Evidence:
- Wrap behavior uses fixed VGA constants
- There is no clear/scroll implementation parameterized by screen geometry
Proof:
- `rg -n "VGA_WIDTH|VGA_HEIGHT|advance_row" -S src/kernel/vga/vga_impl.rs`
- `rg -n "clear.*screen|scroll|geometry" -S src tests || echo "no geometry-aware screen operations yet"`

### Feature B6.3: Provide a configurable geometry preset or build-time selection
Status: ❌ Not done
Evidence:
- No configurable screen preset or geometry selection mechanism exists
Proof:
- `rg -n "DEFAULT_.*GEOMETRY|GEOMETRY_PRESET|ScreenGeometry|screen preset" -S src tests || echo "no configurable geometry preset yet"`

Definition of Done (B6):
- ❌ Not met: screen behavior is still hard-coded to one logical size.
