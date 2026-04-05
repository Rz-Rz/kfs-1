# Phase 3 Research: FPU/MMX/SSE State Ownership

## Question

How should the repo take ownership of FPU/MMX/SSE runtime state without violating the current scalar-first policy, freestanding constraints, or architecture boundaries?

## Findings

### 1. Early init is the correct ownership point

Evidence:
- `src/arch/i386/boot.asm` intentionally does only stack setup and `kmain` handoff.
- `src/kernel/core/init.rs` already sequences ordered runtime validation before helper use.
- Phase 2 already routes SIMD work through `services::simd`.

Implication:
- Phase 3 should extend the existing early-init service path instead of moving work into `boot.asm` or adding a new bypass.

### 2. Runtime ownership is different from execution integration

Evidence:
- `docs/simd_policy.md` separates runtime safety from acceleration policy.
- Phase 4, not Phase 3, owns accelerated helper implementations.
- Phase 2 policy already proved that capability detection and execution permission are separate truths.

Implication:
- Phase 3 can make the machine state ready while still leaving the public execution policy scalar-only until Phase 4 opts in.

### 3. Minimum safe machine-state sequence is conservative

Evidence:
- Intel/OSDev guidance requires clearing `CR0.EM`, clearing `CR0.TS`, setting `CR0.MP`, enabling `CR4.OSFXSR` for SSE state support, and initializing x87/SSE control state explicitly.
- The kernel currently has no multitasking, no user mode, and no FP/SIMD exception handling path.

Implication:
- Use eager ownership, not lazy switching.
- Keep SSE exceptions masked and do not claim task/interrupt preservation yet.
- `FXSAVE`/`FXRSTOR` should remain deferred.

### 4. The runtime policy needs a new “owned but still deferred” state

Evidence:
- `src/kernel/klib/simd.rs` currently distinguishes only `Uninitialized` and `ScalarOnly`.
- Phase 4 will need a positive way to know that runtime state is now owned.

Implication:
- Extend the runtime policy with explicit runtime-ownership fields and a scalar block reason that means “integration deferred,” not “runtime unavailable.”

### 5. Proofs should stay in the repo’s existing style

Evidence:
- `scripts/boot-tests/simd-policy.sh` already validates ordered marker output.
- `scripts/architecture-tests/runtime-ownership.sh` and `scripts/rejection-tests/runtime-ownership-rejections.sh` already enforce the approved ownership graph.
- `scripts/stability-tests/freestanding-simd.sh` is the existing artifact-level SIMD gate.

Implication:
- Phase 3 should extend these proof surfaces rather than creating a separate testing dialect.
- If Phase 3 adds approved control-state instructions, the artifact gate must distinguish them from accidental data-path SIMD usage.

## Recommended Phase Shape

### Plan 03-01
- add typed machine-state initialization helpers
- call them through `services::simd` during early init
- record runtime ownership in the canonical policy state

### Plan 03-02
- document the single-task ownership contract
- encode masked-exception and no-lazy-switching constraints
- keep acceleration deferred until Phase 4

### Plan 03-03
- extend boot, host, architecture, rejection, and stability proofs for runtime ownership
- prove ordering and forced-scalar behavior still hold

## Risks

- If Phase 3 uses SSE control instructions, the artifact gate must be tightened so the repo does not silently permit arbitrary SSE data-path instructions.
- `CR4.OSXMMEXCPT` is not safe to treat as required yet because the kernel does not own the relevant exception path.
- MMX remains the sharp edge because any later MMX helper path must pair usage with `EMMS` cleanup.

---
*Phase: 03-fpu-mmx-sse-state-ownership*
*Researched: 2026-04-05*
