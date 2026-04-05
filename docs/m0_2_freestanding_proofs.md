## M0.2 Freestanding Proofs (No Host Libs)

This repo enforces KFS_1 “no host dependencies / freestanding kernel” (Feature **M0.2**) by
**inspecting the produced kernel ELF** and failing tests if it looks like a hosted, dynamically
linked program.

The goal is not to “trust build flags”, but to **prove properties of the final artifact**.

### What these proofs guarantee (and what they don’t)

These checks guarantee that the kernel artifact:
- Does **not** request a userland dynamic loader/interpreter.
- Does **not** contain dynamic-link metadata that would require runtime resolution of shared libraries.
- Does **not** contain unresolved external references at link time.

These checks do **not** guarantee:
- The kernel boots correctly (that’s covered by QEMU boot tests).
- The kernel prints `42` or implements the subject features (M2–M6).
- The kernel is “correct” or safe—only that it is **self-contained** from a dynamic-linking standpoint.
- Whether MMX/SSE/SSE2 instructions are allowed or forbidden by policy. Freestanding linkage proofs and SIMD policy are separate concerns.

### Where the checks run
- Script: `scripts/boot-tests/freestanding-kernel.sh`
- Hard gate: `make test`

The hard gate (`make test`) checks:
- `build/kernel-i386-test.bin` (fresh test kernel built by `make iso-test`)

Optional (manual) check for the release kernel:
- `KFS_M0_2_INCLUDE_RELEASE=1 bash scripts/boot-tests/freestanding-kernel.sh i386 all`
  (also checks `build/kernel-i386.bin`)

Adversarial / rejection suite:
- `bash scripts/rejection-tests/freestanding-rejections.sh i386 interp-pt-interp-present`
- `bash scripts/rejection-tests/freestanding-rejections.sh i386 dynamic-section-present`
- `bash scripts/rejection-tests/freestanding-rejections.sh i386 unresolved-external-symbol`
- `bash scripts/rejection-tests/freestanding-rejections.sh i386 host-runtime-marker-strings`

### Why the tests require a Rust entry symbol
KFS_1 requires at least two languages (ASM + the chosen language). An ASM-only kernel can
accidentally satisfy the ELF freestanding checks while the chosen language build is still
missing or not linked.

So the script first asserts the final linked kernel includes the real Rust entrypoint by requiring
the symbol `kmain` from the canonical crate-root path (`src/main.rs` -> `src/kernel/core/entry.rs`).
This makes the M0.2 proofs apply to an **ASM + Rust** kernel artifact, not an ASM-only artifact.

---

## Why these checks are valid proofs

### WP-M0.2-1 — No `PT_INTERP` program header
**Test:** fail if `readelf -lW "$KERNEL"` contains `INTERP`.

**Technical meaning:**
`PT_INTERP` is the ELF *program header* used by userland executables to specify the
**dynamic loader (interpreter)** path (commonly something like `ld-linux`).

**Why it proves “no host libs”:**
If `PT_INTERP` exists, the binary is intended to be started by an OS as a process that first
invokes a host dynamic loader. A kernel loaded by GRUB is not executed that way, and it must
not depend on a host interpreter.

**Reference concepts to look up:**
- ELF `PT_INTERP` segment (System V ABI / ELF specification)
- `man readelf` (program headers)

### WP-M0.2-2 — No `.interp` / `.dynamic` sections
**Test:** fail if `readelf -SW "$KERNEL"` contains `.interp` or `.dynamic`.

**Technical meaning:**
- `.interp` is the section that typically stores the interpreter path used by `PT_INTERP`.
- `.dynamic` is the section that contains **dynamic linking metadata** (what shared libraries are needed,
  relocation info for the dynamic loader, etc.).

**Why it proves “no host libs”:**
Presence of these sections indicates the artifact is prepared for **runtime dynamic linking**.
That contradicts a freestanding kernel artifact that must be self-contained and not expect host shared libs.

**Reference concepts to look up:**
- ELF `.dynamic` section and dynamic linking model
- `man readelf` (section headers)

### WP-M0.2-3 — No undefined symbols (`nm -u`)
**Test:** fail if `nm -u "$KERNEL"` outputs anything.

**Technical meaning:**
Undefined symbols in the final linked kernel image mean there are unresolved external references
that were not provided by objects included in the link.

**Why it proves “no host libs”:**
In a freestanding kernel, you do not have a host runtime/linker to resolve missing symbols at boot.
If undefined symbols remain, the kernel is incomplete and (in practice) often indicates accidental reliance
on libc/compiler runtime functions that were not linked in a controlled way.

**Reference concepts to look up:**
- ELF symbol resolution at link time
- `man nm` (undefined symbols)

### WP-M0.2-4 — No libc/loader marker strings (`strings`)
**Test:** fail if `strings "$KERNEL"` matches `(glibc|libc\.so|ld-linux)`.

**Technical meaning:**
This is a **heuristic defense-in-depth** check: many hosted binaries embed well-known identifiers of
glibc, shared library SONAMEs, or the Linux dynamic loader.

**Why it helps:**
This can catch misconfigurations that slip past section-based checks (or remind you you’re accidentally
pulling in hosted assumptions). It is not the primary proof; it is an additional alarm bell.

**Reference concepts to look up:**
- `man strings` (extract printable sequences)

---

## Notes for later (Rust/C)
When the chosen language (Rust) is integrated (M4/M7), these same artifact checks remain valid.
They must continue to pass for the Rust-linked kernel image.

The rejection suite complements the positive proofs above:
- `.interp` / `PT_INTERP` and `.dynamic` cases prove the ELF-metadata checks really trip on
  hosted-runtime baggage.
- The unresolved-symbol case proves a host-dependent external reference is rejected even before a
  runnable kernel artifact can be produced.
- The libc/loader string case proves the heuristic marker checks are wired and fail loudly when
  host-runtime identifiers leak into the image.

For the current MMX/SSE/SSE2 policy, including why SIMD is not itself a host-linkage question, see
[`docs/simd_policy.md`](/home/motero/Code/kfs-1/docs/simd_policy.md).
