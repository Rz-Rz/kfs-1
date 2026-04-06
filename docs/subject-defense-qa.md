# KFS_1 Defense Prep

## 1. What the subject actually requires

From [`docs/subject.pdf`](./subject.pdf), the mandatory part is:

1. A kernel bootable with GRUB.
2. An ASM bootable base.
3. Basic kernel code in the chosen language.
4. Correct freestanding compilation and linking.
5. A custom linker file with GNU `ld`.
6. i386 / x86 architecture.
7. Basic helper functions and types.
8. A screen interface.
9. Display `42` on screen.
10. Keep the work under `10 MB`.

The bonus part includes:

1. Scroll and cursor support.
2. Colors.
3. `printf` / `printk`.
4. Keyboard handling.
5. Multiple screens and shortcuts.
---

## 2. Summary

If someone asks "what does your project do?", the short defense answer is:

> GRUB loads our 32-bit kernel image from a bootable ISO.  
> GRUB transfers control to our Multiboot-compliant ASM entry.  
> The ASM entry sets a minimal CPU state and stack, then calls Rust `kmain`.  
> Rust performs early sanity checks, then prints `42` through our console service, which reaches the VGA text driver.  
> The VGA driver writes text cells to `0xB8000` and controls the hardware cursor through VGA ports.

That single paragraph is the backbone of the whole defense.

---

## 3. The most important questions you must answer directly

## Q1. What is GRUB?

Answer:

GRUB is the bootloader. Its job is not to be the kernel. Its job is to load the kernel image from the boot medium into memory, validate the boot protocol we chose, and transfer control to our kernel entrypoint.

In this repo, GRUB is configured to use Multiboot2.

Proof:

- [`src/arch/i386/grub.cfg`](../src/arch/i386/grub.cfg)
- [`src/arch/i386/multiboot_header.asm`](../src/arch/i386/multiboot_header.asm)

Code:

```cfg
menuentry "kfs 1" {
  multiboot2 /boot/kernel.bin
  boot
}
```

```asm
section .multiboot_header
    dd 0xe85250d6
    dd 0
```

What to say out loud:

- GRUB understands Multiboot.
- We expose a Multiboot2 header in the kernel image.
- GRUB loads `/boot/kernel.bin` and transfers execution to the kernel entrypoint.

---

## Q2. What is Multiboot2 and why do you use it?

Answer:

Multiboot2 is the boot contract between the bootloader and the kernel. It gives GRUB a known format for identifying and loading the kernel correctly. Without that contract, GRUB would not know whether our binary is a valid kernel payload.

Proof:

- [`src/arch/i386/multiboot_header.asm`](../src/arch/i386/multiboot_header.asm)
- [`src/arch/i386/linker.ld`](../src/arch/i386/linker.ld)

Code:

```asm
section .multiboot_header
header_start:
    dd 0xe85250d6
    dd 0
    dd header_end - header_start
    dd 0x100000000 - (0xe85250d6 + 0 + (header_end - header_start))
```

```ld
.boot :
{
    /* ensure that the multiboot header is at the beginning */
    *(.multiboot_header)
}
```

What matters in defense:

- The header exists.
- The linker script places it early in the binary.
- GRUB is told to use `multiboot2`.

---

## Q3. How do things actually get loaded?

Answer:

The loading chain is:

1. The machine boots the ISO.
2. GRUB starts from that ISO.
3. GRUB reads `/boot/kernel.bin`.
4. GRUB recognizes the Multiboot2 header.
5. GRUB jumps to the kernel entrypoint `start`.
6. Our ASM boot code prepares the environment.
7. ASM calls Rust `kmain`.
8. Rust early init runs.
9. Rust prints `42` through the console service and VGA driver.

Proof path:

- [`Makefile`](../Makefile)
- [`src/arch/i386/grub.cfg`](../src/arch/i386/grub.cfg)
- [`src/arch/i386/boot.asm`](../src/arch/i386/boot.asm)
- [`src/kernel/core/entry.rs`](../src/kernel/core/entry.rs)
- [`src/kernel/core/init.rs`](../src/kernel/core/init.rs)

Code:

```asm
start:
    cli
    cld
    mov esp, stack_top
    call kmain
```

```rust
#[no_mangle]
pub extern "C" fn kmain() -> ! {
    match init::run_early_init() {
        Ok(()) => console::start_keyboard_echo_loop(),
        Err(EarlyInitFailure::BssCanary) => runtime_fail("BSS_FAIL"),
        Err(EarlyInitFailure::Layout) => runtime_fail("LAYOUT_FAIL"),
        Err(EarlyInitFailure::StringHelpers) => runtime_fail("STRING_HELPERS_FAIL"),
        Err(EarlyInitFailure::MemoryHelpers) => runtime_fail("MEMORY_HELPERS_FAIL"),
    }
}
```

```rust
pub(crate) fn run_early_init() -> Result<(), EarlyInitFailure> {
    ...
    console::write_bytes(b"42");
    Ok(())
}
```

---

## Q4. What does the ASM boot code do?

Answer:

The ASM code performs the minimal machine-dependent bootstrap before Rust can safely run:

1. Disables interrupts with `cli`.
2. Clears direction flag with `cld`.
3. Installs a stack with `mov esp, stack_top`.
4. Calls `kmain`.
5. Falls into a halt loop if execution ever returns.

Proof:

- [`src/arch/i386/boot.asm`](../src/arch/i386/boot.asm)

Code:

```asm
start:
    cli
    cld
    mov esp, stack_top
    call kmain

halt_loop:
    cli
    hlt
    jmp halt_loop
```

Why this matters:

- Rust cannot be the very first instruction stream here because we still need a valid low-level handoff.
- This is exactly why the subject asks for an ASM bootable base.

---

## Q5. Why do you need a custom linker script?

Answer:

Because a kernel is not a normal userland program. We must control where sections go, where the image starts in memory, where the Multiboot header lives, and where layout symbols such as `kernel_start`, `bss_start`, and `kernel_end` are exported.

The subject explicitly forbids using the host's linker script.

Proof:

- [`src/arch/i386/linker.ld`](../src/arch/i386/linker.ld)
- [`Makefile`](../Makefile)

Code:

```ld
ENTRY(start)

SECTIONS {
    . = 1M;
    kernel_start = .;

    .boot : { *(.multiboot_header) }
    .text : { *(.text .text.*) }
    .rodata : { *(.rodata .rodata.*) }
    .data : { *(.data .data.*) }
    .bss : {
        bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        bss_end = .;
    }

    kernel_end = .;
}
```

```make
@env $(repro_env) ld -m elf_i386 -n -T $(linker_script) -o $(kernel) ...
```

Defense sentence:

> We use the host `ld` binary, but not the host linker script. We provide our own `linker.ld`, which is exactly what the subject requires.

---

## Q6. Why is i386 mandatory, and where is that enforced?

Answer:

The subject explicitly requires i386 / x86. In this repo that is enforced at the artifact and boot level:

1. Build defaults to `i386`.
2. NASM outputs `elf32`.
3. `ld` links with `-m elf_i386`.
4. Runtime uses `qemu-system-i386`.

Proof:

- [`Makefile`](../Makefile)

Code:

```make
arch ?= $(if $(ARCH),$(ARCH),i386)
...
@env $(repro_env) nasm -felf32 $< -o $@
...
@env $(repro_env) ld -m elf_i386 -n -T $(linker_script) -o $(kernel) ...
...
@qemu-system-i386 -cdrom $(iso)
```

Important nuance:

- The repo's Rust target is currently `i586-unknown-linux-gnu`, but the linked artifact and boot path remain ELF32 / i386.
- If asked, explain that the repo documents this choice in architecture docs because of current Rust/SSE2 target policy, but the subject-facing artifact is still a 32-bit x86 kernel.

---

## Q7. What does “freestanding” mean here?

Answer:

Freestanding means the kernel is not linked like a hosted userland program. It must not depend on the host's libc, loader, or runtime environment. GRUB loads it directly; Linux userspace does not.

In practice:

1. No standard library.
2. No host dynamic loader.
3. No unresolved external symbols.
4. No libc dependency.
5. The kernel owns its own low-level runtime assumptions.

Proof:

- [`src/main.rs`](../src/main.rs)
- [`Makefile`](../Makefile)
- [`scripts/boot-tests/freestanding-kernel.sh`](../scripts/boot-tests/freestanding-kernel.sh)
- [`docs/m0_2_freestanding_proofs.md`](./m0_2_freestanding_proofs.md)

Code:

```rust
#![no_std]
#![no_main]
#![no_builtins]
```

```make
@env $(repro_env) rustc \
    --crate-type lib \
    --target $(rust_target) \
    --emit=obj \
    -C panic=abort \
    -C force-unwind-tables=no \
```

```bash
if readelf -lW "${kernel}" | grep -qE '^[[:space:]]*INTERP[[:space:]]'; then
    echo "FAIL ${kernel}: PT_INTERP present (dynamic loader required)"
fi

if readelf -SW "${kernel}" | grep -qE '[[:space:]]\.dynamic[[:space:]]'; then
    echo "FAIL ${kernel}: .dynamic section present"
fi

if [[ -n "$(nm -u "${kernel}" | head -n 1)" ]]; then
    echo "FAIL ${kernel}: undefined symbols present"
fi
```

The correct defense point is:

> We do not only claim freestanding because of flags. We prove it by inspecting the final kernel ELF.

---

## Q8. The subject lists flags like `-fno-builtin`, `-nostdlib`, `-nodefaultlibs`. How do you defend that in Rust?

Answer:

Those subject flags are given as C++ examples. In Rust, the exact spelling is different, but the intent is the same:

1. `#![no_std]` replaces the hosted standard library.
2. `#![no_main]` avoids a hosted runtime entry model.
3. `#![no_builtins]` rejects compiler builtin assumptions at the crate level.
4. `-C panic=abort` avoids unwind-based runtime behavior.
5. We emit an object and manually link it into the kernel with our own linker script.
6. We then prove the final ELF has no loader or dynamic-link metadata.

Proof:

- [`src/main.rs`](../src/main.rs)
- [`Makefile`](../Makefile)
- [`docs/m0_2_freestanding_proofs.md`](./m0_2_freestanding_proofs.md)

Do not say:

> We used the same flags as in the PDF.

Say instead:

> The PDF gives C++ examples. In Rust, we implement the same freestanding constraints with `no_std`, `no_main`, manual linking, and final-ELF proof checks.

---

## Q9. How do you prove the kernel really reaches Rust and is not just an ASM-only fake?

Answer:

This repo explicitly checks that the linked kernel contains the Rust entry symbol `kmain`, and the boot path calls it.

Proof:

- [`src/arch/i386/boot.asm`](../src/arch/i386/boot.asm)
- [`src/kernel/core/entry.rs`](../src/kernel/core/entry.rs)
- [`scripts/boot-tests/freestanding-kernel.sh`](../scripts/boot-tests/freestanding-kernel.sh)

Code:

```asm
extern kmain
...
call kmain
```

```rust
#[no_mangle]
pub extern "C" fn kmain() -> ! {
    ...
}
```

```bash
if ! nm -n "${kernel}" | grep -qw 'kmain'; then
    echo "FAIL ${kernel}: Rust entry symbol missing (kmain)"
fi
```

That last check matters because:

- An ASM-only kernel could still look bootable.
- The subject requires ASM plus the chosen language.
- So this repo proves the Rust path is present in the actual linked kernel.

---

## Q10. What is QEMU?

Answer:

QEMU is the machine emulator and virtual machine runner used by this repo to boot and test the kernel. It emulates a 32-bit x86 PC platform, so we can boot the GRUB ISO, run the kernel, and observe serial output, VGA output, and VNC-driven UI behavior.

Proof:

- [`Makefile`](../Makefile)
- [`README.md`](../README.md)

Code:

```make
@qemu-system-i386 -cdrom $(iso)
```

```md
- Runs headless QEMU boot/runtime checks
- Asserts the first VGA text-memory bytes for `42`
```

What to say:

> QEMU is the execution environment for our automated proof. It gives us reproducible x86 virtual hardware for boot, runtime, serial, and VGA tests.

---

## Q11. Why QEMU and not something else?

Answer:

The subject allows other virtual managers. This repo uses QEMU because it fits the actual engineering needs:

1. It supports `i386` directly.
2. It is scriptable and CI-friendly.
3. It runs headless.
4. It exposes serial and monitor/VNC interfaces that are easy to automate.
5. The entire test harness in this repo is built around it.

Important distinction:

- QEMU is the emulator / VM frontend.
- KVM is optional hardware acceleration for QEMU on Linux.

Proof:

- [`README.md`](../README.md)
- [`Makefile`](../Makefile)

Code:

```md
Optional: if your host has KVM and you want acceleration
- `KFS_USE_KVM=1 make test`
```

This means:

- QEMU is the base execution tool.
- KVM is optional acceleration.
- CI and many hosts still run without KVM.

---

## Q12. How does the kernel actually print to the screen?

Answer:

The call path is:

1. Rust early init decides normal startup succeeded.
2. `core::init` calls `console::write_bytes(b"42")`.
3. The console service delegates to the VGA text driver.
4. The VGA driver writes packed text cells to VGA memory at `0xB8000`.

Proof:

- [`src/kernel/core/init.rs`](../src/kernel/core/init.rs)
- [`src/kernel/services/console.rs`](../src/kernel/services/console.rs)
- [`src/kernel/drivers/vga_text/writer.rs`](../src/kernel/drivers/vga_text/writer.rs)

Code:

```rust
console::write_bytes(b"42");
```

```rust
pub(crate) fn write_bytes(bytes: &[u8]) {
    vga_text::write_bytes(bytes);
}
```

```rust
const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;

for (index, cell) in shadow.iter().enumerate() {
    unsafe {
        core::ptr::write_volatile(VGA_TEXT_BUFFER.add(index), *cell);
    }
}
```

This is the exact mandatory screen path.

---

## Q13. What is VGA text mode?

Answer:

VGA text mode is the classic PC text display mode where screen cells are stored in a memory region. Each cell is typically a 16-bit packed value containing:

1. The ASCII character byte.
2. The attribute / color byte.

This repo writes directly to that memory area at `0xB8000`.

Proof:

- [`src/kernel/drivers/vga_text/writer.rs`](../src/kernel/drivers/vga_text/writer.rs)

Code:

```rust
const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
```

Defense phrasing:

> The visible screen text is not printed through an OS API. We directly update the VGA text framebuffer in memory.

---

## Q14. What is the difference between VGA memory and VGA ports?

Answer:

There are two different hardware interaction styles here:

1. Memory-mapped access:
   the visible text buffer is written at `0xB8000`.
2. Port-mapped access:
   VGA control registers such as the hardware cursor are accessed through I/O ports like `0x3D4` and `0x3D5`.

Proof:

- [`src/kernel/drivers/vga_text/writer.rs`](../src/kernel/drivers/vga_text/writer.rs)
- [`src/kernel/machine/port.rs`](../src/kernel/machine/port.rs)

Code:

```rust
const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;
const VGA_CRTC_ADDR_PORT: Port = Port::new(0x3D4);
const VGA_CRTC_DATA_PORT: Port = Port::new(0x3D5);
```

```rust
pub unsafe fn read_u8(self) -> u8 {
    asm!("in al, dx", in("dx") self.0, out("al") value, ...);
}

pub unsafe fn write_u8(self, value: u8) {
    asm!("out dx, al", in("dx") self.0, in("al") value, ...);
}
```

This is one of the most likely oral-defense questions.

---

## Q15. What is the `Port` type and why do you have it?

Answer:

`Port` is the typed wrapper for x86 port I/O. Instead of scattering raw inline assembly everywhere, the repo concentrates the `in` / `out` instructions in one low-level machine abstraction.

Proof:

- [`src/kernel/machine/port.rs`](../src/kernel/machine/port.rs)

Code:

```rust
#[repr(transparent)]
pub struct Port(u16);

impl Port {
    pub const fn new(value: u16) -> Self { Self(value) }
    pub const fn offset(self, delta: u16) -> Self { Self(self.0.wrapping_add(delta)) }
}
```

Why this is a good defense answer:

- It shows layering.
- It shows why port I/O belongs in machine code ownership, not in high-level services.

---

## Q16. What are the “different parts” this repo uses?

Answer:

You should be able to name them cleanly:

1. `GRUB`
   loads the kernel from the ISO.
2. `Multiboot2 header`
   advertises a GRUB-compatible kernel image.
3. `boot.asm`
   installs minimal CPU state and stack, then calls Rust.
4. `linker.ld`
   controls section layout and exported symbols.
5. `src/main.rs`
   freestanding Rust crate root.
6. `src/lib.rs`
   host-testable shared crate root.
7. `src/kernel/core/entry.rs`
   owns `kmain`.
8. `src/kernel/core/init.rs`
   owns early init and the mandatory `42` success path.
9. `src/kernel/services/console.rs`
   service-level console interface.
10. `src/kernel/drivers/vga_text/`
    VGA text driver.
11. `src/kernel/machine/port.rs`
    typed x86 port I/O.
12. `QEMU`
    execution and testing environment.
13. `nasm`, `rustc`, `ld`, `grub-mkrescue`
    build chain.

If you can explain each part's job in one sentence, you are in good shape.

---

## Q17. Why are there two Rust crate roots?

Answer:

Because the repo separates:

1. The freestanding kernel root.
2. The host-testable library root.

The freestanding root is [`src/main.rs`](../src/main.rs).  
The host-linked root is [`src/lib.rs`](../src/lib.rs).

Both share the same kernel module tree under `src/kernel/`.

Proof:

- [`src/main.rs`](../src/main.rs)
- [`src/lib.rs`](../src/lib.rs)

Code:

```rust
// src/main.rs
#![no_std]
#![no_main]
#![no_builtins]

mod freestanding;
pub mod kernel;
```

```rust
// src/lib.rs
#![no_std]

pub mod kernel;
```

Defense point:

> We do not maintain separate fake production trees for tests. The shared subsystem tree is real, and tests link through `src/lib.rs`.

---

## Q18. What is the “basic kernel library” in this repo?

Answer:

It is the freestanding helper layer under `src/kernel/klib/`.  
That is where the repo owns helper families like:

1. string helpers
2. memory helpers
3. SIMD policy support for memory backends

This corresponds directly to the subject asking for basic helpers like `strlen` and `strcmp`.

Proof:

- [`src/kernel/klib/string/mod.rs`](../src/kernel/klib/string/mod.rs)
- [`src/kernel/klib/memory/mod.rs`](../src/kernel/klib/memory/mod.rs)
- [`src/kernel/core/init.rs`](../src/kernel/core/init.rs)

Useful defense line:

> We reimplement foundational helpers because a freestanding kernel cannot rely on host libc.

---

## Q19. How do you prove the subject requirement “display 42” is actually satisfied?

Answer:

There are three levels of proof in this repo:

1. Source-level proof:
   `core::init` writes `b"42"`.
2. Runtime path proof:
   the boot path reaches Rust early init.
3. Artifact / memory proof:
   tests inspect VGA text memory and confirm the first bytes are the expected `42`.

Proof:

- [`src/kernel/core/init.rs`](../src/kernel/core/init.rs)
- [`README.md`](../README.md)

Code:

```rust
console::write_bytes(b"42");
```

```md
- The mandatory screen path prints `42` and VGA text memory begins with the expected `42` bytes
```

This is better than saying only:

> I saw 42 on screen once.

Because the repo has automated proof, not just a manual claim.

---

## Q20. How do you prove the project stays under 10 MB?

Answer:

The size cap is not hand-waved. The repo checks the ISO and IMG sizes directly in the test workflow.

Proof:

- [`README.md`](../README.md)
- [`Makefile`](../Makefile)

Defense answer:

> The subject sets a hard upper bound of 10 MB, and our test workflow checks release image size as part of `make test`.

---

## 4. The exact boot flow in this repo

If the evaluator says "explain the boot path from power-on to screen output", this is the answer:

1. The machine boots the ISO created by `grub-mkrescue`.
2. GRUB reads [`src/arch/i386/grub.cfg`](../src/arch/i386/grub.cfg) and loads `/boot/kernel.bin` using `multiboot2`.
3. The kernel image contains a Multiboot2 header from [`src/arch/i386/multiboot_header.asm`](../src/arch/i386/multiboot_header.asm), placed early by [`src/arch/i386/linker.ld`](../src/arch/i386/linker.ld).
4. Control enters the ASM symbol `start` in [`src/arch/i386/boot.asm`](../src/arch/i386/boot.asm).
5. ASM disables interrupts, clears the direction flag, sets up the stack, and calls `kmain`.
6. Rust enters [`src/kernel/core/entry.rs`](../src/kernel/core/entry.rs).
7. `kmain` calls [`src/kernel/core/init.rs`](../src/kernel/core/init.rs).
8. Early init validates BSS and layout, initializes runtime policy, validates helper families, then calls `console::write_bytes(b"42")`.
9. [`src/kernel/services/console.rs`](../src/kernel/services/console.rs) forwards to the VGA driver.
10. [`src/kernel/drivers/vga_text/writer.rs`](../src/kernel/drivers/vga_text/writer.rs) writes the packed screen cells to `0xB8000`.

That is the single most important full-path explanation in the whole defense.

---

## 5. The best short code excerpts to memorize

## Freestanding Rust root

Source:

- [`src/main.rs`](../src/main.rs)

```rust
#![no_std]
#![no_main]
#![no_builtins]

mod freestanding;
pub mod kernel;
```

Why memorize it:

- It is the cleanest subject-facing proof that this is not a normal hosted Rust binary.

## GRUB config

Source:

- [`src/arch/i386/grub.cfg`](../src/arch/i386/grub.cfg)

```cfg
menuentry "kfs 1" {
  multiboot2 /boot/kernel.bin
  boot
}
```

Why memorize it:

- It proves exactly how GRUB is told to load the kernel.

## ASM boot handoff

Source:

- [`src/arch/i386/boot.asm`](../src/arch/i386/boot.asm)

```asm
start:
    cli
    cld
    mov esp, stack_top
    call kmain
```

Why memorize it:

- It is the shortest explanation of the ASM base and Rust handoff.

## Rust entrypoint

Source:

- [`src/kernel/core/entry.rs`](../src/kernel/core/entry.rs)

```rust
#[no_mangle]
pub extern "C" fn kmain() -> ! {
    match init::run_early_init() {
        Ok(()) => console::start_keyboard_echo_loop(),
        Err(EarlyInitFailure::BssCanary) => runtime_fail("BSS_FAIL"),
        Err(EarlyInitFailure::Layout) => runtime_fail("LAYOUT_FAIL"),
        Err(EarlyInitFailure::StringHelpers) => runtime_fail("STRING_HELPERS_FAIL"),
        Err(EarlyInitFailure::MemoryHelpers) => runtime_fail("MEMORY_HELPERS_FAIL"),
    }
}
```

Why memorize it:

- It proves the chosen-language entry is real, not theoretical.

## Mandatory `42` write path

Source:

- [`src/kernel/core/init.rs`](../src/kernel/core/init.rs)

```rust
pub(crate) fn run_early_init() -> Result<(), EarlyInitFailure> {
    ...
    console::write_bytes(b"42");
    Ok(())
}
```

Why memorize it:

- This is the mandatory success path.

## VGA memory write

Source:

- [`src/kernel/drivers/vga_text/writer.rs`](../src/kernel/drivers/vga_text/writer.rs)

```rust
const VGA_TEXT_BUFFER: *mut u16 = 0xb8000 as *mut u16;

core::ptr::write_volatile(VGA_TEXT_BUFFER.add(index), *cell);
```

Why memorize it:

- It is the clearest hardware-facing proof that the screen path is real.

## Port I/O

Source:

- [`src/kernel/machine/port.rs`](../src/kernel/machine/port.rs)

```rust
asm!("in al, dx", in("dx") self.0, out("al") value, ...);
asm!("out dx, al", in("dx") self.0, in("al") value, ...);
```

Why memorize it:

- It lets you explain port-mapped I/O concretely.

---

## 6. The best live-proof commands if someone challenges you

If you want to prove things live in a terminal, these are the strongest ones:

```bash
make test
```

```bash
readelf -h build/kernel-i386.bin
```

```bash
readelf -lW build/kernel-i386.bin | rg INTERP
```

```bash
readelf -SW build/kernel-i386.bin | rg '\.interp|\.dynamic'
```

```bash
nm -n build/kernel-i386.bin | rg '\bkmain\b|\bstart\b'
```

```bash
objdump -d build/kernel-i386.bin | sed -n '/<start>:/,/^$/p'
```

```bash
file build/os-i386.iso
wc -c build/os-i386.iso
```

What each one proves:

- `make test`: the repo's umbrella verification.
- `readelf -h`: ELF32 / x86 artifact identity.
- `readelf -lW`: absence of hosted dynamic loader.
- `readelf -SW`: absence of hosted dynamic-link sections.
- `nm`: entry symbols exist.
- `objdump`: `start` really calls `kmain`.
- `file` and `wc -c`: bootable ISO type and size discipline.

---

## 7. The strongest oral-defense phrasing to reuse

Use these exact shapes of answers.

### "What is GRUB in your project?"

> GRUB is our bootloader. It is responsible for loading the kernel from the ISO and transferring control through the Multiboot2 contract. It is not the kernel itself.

### "How does your kernel start?"

> GRUB loads the kernel, jumps to our ASM `start`, ASM sets up stack and CPU state, then calls Rust `kmain`, and Rust early init prints `42`.

### "How do you know you are not using host libraries?"

> We prove it on the final ELF. The repo rejects `PT_INTERP`, `.interp`, `.dynamic`, undefined external symbols, and libc/loader markers. So we do not merely trust compile flags.

### "Why QEMU?"

> Because it gives us a reproducible `i386` virtual machine that is scriptable and CI-friendly. It lets us boot GRUB, run the kernel, and inspect serial and VGA behavior automatically.

### "How does the screen output work?"

> The success path writes `42` through the console service into the VGA text driver, which writes packed text cells to `0xB8000` and controls the cursor through VGA ports.

---

## 8. The questions most likely to catch you if you are not ready

Be ready for these specifically:

1. Why do you need ASM before Rust?
2. Why do you need a custom linker script?
3. What is the difference between a bootloader and a kernel?
4. What is Multiboot2 actually buying you?
5. Why is `0xB8000` not just a random address?
6. What is the difference between writing screen memory and writing a VGA control port?
7. Why is final-ELF proof stronger than build-flag claims?
8. Why can a kernel not rely on `libc`?
9. Why do you say GRUB loads `kernel.bin` and not an ELF executable like Linux userspace would?
10. What exact line in your code shows the chosen-language entrypoint is real?

If you cannot answer those smoothly, you are not ready.

---

## 9. Bottom line

If you only memorize five things, memorize these:

1. GRUB loads `/boot/kernel.bin` using Multiboot2.
2. ASM `start` sets machine state and calls Rust `kmain`.
3. The kernel is freestanding, and this repo proves it by inspecting the final ELF.
4. The mandatory success path is `console::write_bytes(b"42")`.
5. The VGA driver writes directly to `0xB8000` and uses ports `0x3D4` / `0x3D5` for cursor control.

If you can explain those five points clearly, you can survive most of the defense.
