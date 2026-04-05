# KFS-1 SIMD/MMX Enablement

## What This Is

This is a brownfield planning and execution track for adding optional MMX/SSE/SSE2 acceleration to the existing KFS-1 freestanding 32-bit x86 kernel. The work is constrained by the course subject, the repo's dual-root Rust architecture, and the requirement that the final kernel remain bootable via GRUB without host runtime linkage.

## Core Value

Enable SIMD acceleration only if it is architecturally safe, freestanding, and fully compatible with the kernel's boot/runtime contract.

## Requirements

### Validated

- ✓ GRUB boots the kernel image and hands off into the chosen-language kernel entry
- ✓ The kernel remains freestanding and statically linked with no host runtime dependencies
- ✓ Shared Rust production logic is exposed through `src/kernel/mod.rs` and host tests link through `src/lib.rs`
- ✓ Current runtime proves early-init, serial diagnostics, and VGA text output behavior through `make test`

### Active

- [ ] Define an explicit CPU baseline and feature-policy story for MMX/SSE/SSE2 work
- [ ] Add safe runtime ownership for FPU/MMX/SSE state before any accelerated instruction path is used
- [ ] Introduce optional accelerated helper routines with scalar fallback
- [ ] Extend verification so subject compliance and freestanding proofs remain true after SIMD work

### Out of Scope

- x86_64, AVX, AVX2, or wider-vector enablement — not needed for the subject or current kernel stage
- User-mode or multitasking SIMD context virtualization — defer until the kernel actually owns multiple execution contexts
- "Just flip compiler flags" acceleration — rejected because runtime safety and ABI policy must be explicit first

## Context

The existing codebase is a small freestanding kernel with strong architectural test discipline. Rust currently builds the freestanding object with `i586-unknown-linux-gnu` because stable Rust's `i686-unknown-linux-gnu` target carries an SSE2 ABI requirement that conflicts with the repo's current no-SSE artifact policy. The repo already has a stability gate preventing accidental XMM/SSE instruction emission, but it does not yet own CPU feature detection, CR0/CR4/MXCSR bring-up, or FPU/SSE state management.

## Constraints

- **Subject**: 32-bit x86, GRUB boot, no host runtime linkage — core course rules
- **Architecture**: dual Rust crate roots with one shared module tree — must preserve `src/main.rs` / `src/lib.rs` discipline
- **Runtime Safety**: no SIMD instruction may execute before the kernel owns the required machine state — prevents boot/runtime corruption
- **Verification**: `make test` remains the umbrella repo gate — SIMD work must extend, not bypass, the existing proof harness
- **Compatibility**: current branch should prefer optional acceleration with scalar fallback over raising the minimum CPU baseline prematurely

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Plan SIMD work as a phased architecture effort, not a flag tweak | ABI, boot, and runtime state ownership must be introduced deliberately | — Pending |
| Prefer optional acceleration with scalar fallback | Keeps the branch closer to subject-era hardware expectations and avoids forced SSE2 baseline escalation | — Pending |
| Keep freestanding/no-host-linkage proofs as first-class acceptance criteria | The subject constraint is non-negotiable | ✓ Good |
| Use GSD planning artifacts on a dedicated branch | Low-level SIMD work needs explicit scope, ordering, and traceability | ✓ Good |

---
*Last updated: 2026-04-05 after GSD branch bootstrap*
