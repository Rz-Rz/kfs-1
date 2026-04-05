# Phase 1: SIMD Policy & Subject Contract - Research

**Researched:** 2026-04-05
**Status:** Ready for planning

## Objective

Define what the branch must state now so later MMX/SSE/SSE2 enablement work is technically coherent, subject-compliant, and consistent with the repo's existing freestanding architecture.

## Findings

### 1. The subject does not explicitly forbid MMX/SSE/SSE2

`docs/subject.pdf` requires:
- 32-bit x86 (`i386 (x86)`) as the mandatory architecture
- GRUB bootability
- no host runtime dependencies (`-nostdlib`, `-nodefaultlibs` in the C/C++ example)

It does not explicitly require that FPU, MMX, SSE, or SSE2 be disabled.

**Implication for Phase 1:**
- The policy must not claim "SSE is forbidden by the subject"
- The policy should instead separate:
  - subject constraints
  - host-linkage constraints
  - CPU baseline policy
  - runtime safety prerequisites

### 2. SIMD use is not the same thing as host linkage

The repo's freestanding proof in `docs/m0_2_freestanding_proofs.md` is about final ELF properties:
- no interpreter
- no dynamic section
- no unresolved externals

Those are linkage/runtime-loader properties, not instruction-set properties.

**Implication for Phase 1:**
- The policy must say explicitly that SSE/SSE2 instructions do not themselves imply glibc or host-loader linkage
- Later phases must preserve the freestanding ELF proof independently of SIMD policy

### 3. The current Rust target compromise is about ABI and codegen, not subject wording

The repo currently builds Rust with `i586-unknown-linux-gnu` in `Makefile`.

Relevant current-state facts already recorded in repo docs:
- `docs/kernel_architecture.md` now states that the final artifact is still ELF32 `Intel 80386`
- the same doc also states that Rust codegen currently uses `i586-unknown-linux-gnu`

The reason for the switch is the current stable Rust toolchain behavior:
- `i686-unknown-linux-gnu` now carries an SSE2-based ABI expectation
- disabling `sse2` on that target is being phased into a hard error

**Implication for Phase 1:**
- The policy note must capture the `i386` subject wording versus `i586` Rust codegen compromise without overstating compatibility
- The policy should treat strict 80386 compatibility as an open limitation, not solved fact

### 4. Later SIMD work needs runtime ownership before any accelerated path is legal

Current repo reality:
- `src/arch/i386/boot.asm` sets stack state and jumps to `kmain`
- no visible FPU/MMX/SSE bring-up or state-management path exists in the analyzed code
- the current stability gate forbids accidental XMM/SSE-family instruction emission in the freestanding artifact

**Implication for Phase 1:**
- The branch must not enable MMX/SSE/SSE2 by compiler flag alone
- The policy must state that later phases need:
  - capability detection / policy gating
  - machine-state initialization
  - explicit save/restore or execution-boundary constraints
  - proof obligations for all of the above

### 5. Ownership boundaries must be written before implementation

Existing repo discipline already says:
- shared Rust ownership stays under `src/kernel/mod.rs`
- low-level machine primitives live under `src/kernel/machine/`
- unavoidable raw assembly/runtime helpers stay under `src/arch/`
- docs and test guidance must change with architecture changes

**Implication for Phase 1:**
- Future SIMD/MMX/SSE code should be split across:
  - policy/bring-up and unavoidable machine state boundaries in `arch` and/or `core`
  - typed low-level helper surface in `machine`
  - scalar/accelerated helper dispatch in `klib`
- The Phase 1 policy note should make those ownership expectations explicit

## Recommended Output for This Phase

Phase 1 should land:
- a dedicated `docs/simd_policy.md` note
- cross-links/alignment updates in `docs/kernel_architecture.md`
- freestanding-proof wording updates in `docs/m0_2_freestanding_proofs.md`

That note should cover:
1. what the subject does and does not require
2. why SSE/SSE2 is not a host-linkage issue
3. the current `i586` target compromise and its limitation
4. prerequisites for future MMX/SSE/SSE2 use
5. ownership boundaries for later phases
6. verification obligations for later phases
7. explicit open risks

## Open Risks to Record

- The repo does not currently prove absence of all floating-point instructions, only XMM/SSE-family patterns.
- The branch does not yet decide whether future acceleration remains optional forever or eventually raises the CPU baseline.
- Strict 80386 compatibility is not guaranteed by the current Rust codegen target choice.
- MMX-specific cleanup requirements and x87 interaction rules must be handled deliberately in later phases.

## Validation Architecture

For Phase 1, validation is documentation- and parse-oriented rather than behavior-oriented.

Recommended checks:
- `node ~/.codex/get-shit-done/bin/gsd-tools.cjs roadmap analyze >/dev/null`
- `node ~/.codex/get-shit-done/bin/gsd-tools.cjs init progress >/dev/null`
- `make test-plain`

Why this is enough for Phase 1:
- the phase is policy/documents only
- the branch must still prove it did not break the existing build/test contract

---
*Phase: 01-simd-policy-subject-contract*
*Research captured: 2026-04-05*
