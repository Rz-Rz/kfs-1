# Codebase Concerns

**Analysis Date:** 2026-04-05

## Tech Debt

**SIMD/FPU runtime ownership:**
- Issue: the repo currently forbids SSE/XMM instructions in freestanding artifacts but has no implemented FPU/MMX/SSE initialization path
- Why: the kernel is still in an early single-address-space stage focused on basic boot/runtime proofs
- Impact: SIMD acceleration cannot be enabled safely without new runtime ownership code
- Fix approach: add explicit CPU feature policy, control-register bring-up, and state-management rules before any accelerated routines

**CPU baseline wording vs codegen baseline:**
- Issue: subject wording says `i386 (x86)` while Rust codegen currently uses `i586-unknown-linux-gnu`
- Why: stable Rust `i686-unknown-linux-gnu` now carries an SSE2 ABI requirement that conflicts with the repo's current no-SSE policy
- Impact: strict 80386 compatibility is not currently guaranteed by Rust-generated instructions
- Fix approach: either keep the documented compromise explicit or move to a custom target/policy if strict baseline compatibility becomes mandatory

**Freestanding SIMD proof scope:**
- Issue: the current no-SIMD script catches XMM/SSE-family patterns but is not a complete "no floating-point instructions at all" proof
- Why: the current gate was written to prevent accidental SSE/XMM emission specifically
- Impact: x87-related regressions could escape if SIMD work is introduced carelessly
- Fix approach: widen verification strategy or document the exact policy boundary

## Known Bugs

**No confirmed runtime bug is currently documented for the analyzed tree.**
- The main risks are architectural gaps and future-regression hazards rather than a known open defect list.

## Security Considerations

**Unsafe low-level code:**
- Risk: incorrect inline assembly, pointer math, or linker assumptions can corrupt memory or break boot
- Current mitigation: architecture tests, narrow ownership rules, and shell rejection tests
- Recommendations: keep SIMD/FPU code behind small audited boundaries with explicit invariants

**Artifact trust drift:**
- Risk: docs and tests can silently drift from current build/runtime reality
- Current mitigation: `AGENTS.md` requires docs/test guidance updates in the same change
- Recommendations: keep SIMD policy docs and proof scripts coupled to implementation changes

## Performance Bottlenecks

**Scalar memory helpers:**
- Problem: `memcpy` and `memset` are obvious future hot paths still handled by scalar routines
- Measurement: no benchmark suite is present in the current tree
- Cause: the kernel is correctness-first and currently avoids SIMD setup complexity
- Improvement path: optional accelerated implementations with strict scalar fallback and semantic parity tests

**Screen-buffer movement:**
- Problem: VGA buffer writes and future scroll/blit paths can become byte/word-movement hot spots
- Measurement: no timing data is present
- Cause: simple correctness-oriented implementations
- Improvement path: revisit after memory-helper acceleration and runtime safety work land

## Fragile Areas

**Boot/linker boundary:**
- Why fragile: symbol names, section ordering, and calling conventions must match exactly
- Common failures: broken boot handoff, missing layout symbols, bad section placement
- Safe modification: change `src/arch/i386/*`, `src/kernel/core/entry.rs`, and linker/test proofs together
- Test coverage: strong shell coverage exists, but it is easy to break with small low-level edits

**Dual crate-root architecture:**
- Why fragile: fake-root testing shortcuts would undermine the intended production boundary
- Common failures: test-only path hacks, duplicate module trees, drift between `src/main.rs` and `src/lib.rs`
- Safe modification: keep shared logic under `src/kernel/mod.rs` only
- Test coverage: strong architecture/rejection coverage

**Future SIMD work:**
- Why fragile: control-register policy, instruction selection, and save/restore behavior cut across arch, machine, klib, and tests
- Common failures: executing SIMD before init, assuming SSE2-only CPUs, or breaking freestanding proofs
- Safe modification: phase the work and keep proof scripts evolving with each step
- Test coverage: currently incomplete for FPU/SSE state handling

## Scaling Limits

**Execution model:**
- Current capacity: single boot/runtime flow with no demonstrated task switching or user-mode state isolation
- Limit: any feature that needs preserved per-task FP/SIMD state will outgrow the current model
- Symptoms at limit: undefined behavior or state corruption once more than one execution context must preserve FP/SIMD registers
- Scaling path: define and implement explicit context-save rules before broader SIMD adoption

## Dependencies at Risk

**Rust target policy:**
- Risk: stable Rust continues tightening ABI rules around x86 targets and target features
- Impact: ad hoc target-flag workarounds can stop compiling
- Migration plan: keep to target-level ABI contracts or introduce a justified custom target when needed

## Missing Critical Features

**CPU capability detection for optional acceleration:**
- Problem: no first-class CPUID/feature-policy path exists for MMX/SSE/SSE2 decisions
- Current workaround: global "no SSE in kernel artifact" policy
- Blocks: safe optional acceleration
- Implementation complexity: medium

**FPU/MMX/SSE state management:**
- Problem: no CR0/CR4/MXCSR bring-up or save/restore boundary is present
- Current workaround: do not execute SIMD/X87-sensitive accelerated paths
- Blocks: real SIMD enablement
- Implementation complexity: high

## Test Coverage Gaps

**SIMD runtime policy:**
- What's not tested: CPUID gating, control-register initialization, MMX cleanup, SSE state preservation
- Risk: low-level regressions could boot-fail or corrupt state silently
- Priority: High
- Difficulty to test: Medium to High because the proof needs both host semantics and QEMU/runtime checks

---
*Concerns audit: 2026-04-05*
*Update as issues are fixed or new ones are discovered*
