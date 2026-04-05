# Phase 2 Research: Capability Detection & Runtime Guardrails

## Question

How should the repo introduce CPU feature detection and a canonical scalar-only guardrail without violating the existing architecture rules?

## Findings

### 1. The current low-level seam already exists in `arch -> core`

Evidence:
- `src/arch/i386/runtime_io.asm` exports test/runtime helpers under the `kfs_arch_*` prefix.
- `src/kernel/core/entry.rs` owns the extern ABI boundary for those helpers.
- `scripts/architecture-tests/runtime-ownership.sh` enforces the `boot -> kmain -> core init` path.

Implication:
- Phase 2 can extend the current `kfs_arch_*` surface with CPUID helpers without inventing a new ownership pattern.

### 2. `core -> machine` is currently blocked by architecture enforcement

Evidence:
- `scripts/architecture-tests/layer-dependencies.sh` case `core-depends-only-on-services-types-klib` rejects `core` imports from `machine`.
- `docs/simd_policy.md` says `core` owns sequencing while `machine` owns typed low-level primitives, but the current enforced graph still blocks a direct module import.

Implication:
- The safe Phase 2 move is to keep CPUID access at the existing arch-helper boundary.
- If the repo ever wants a `machine::cpu` typed primitive, that should be a deliberate later architecture change rather than an accidental Phase 2 side effect.

### 3. `klib` needs a guardrail seam, but it cannot import runtime policy directly

Evidence:
- `scripts/architecture-tests/layer-dependencies.sh` case `klib-does-not-depend-on-device-code` forbids `klib` imports from `core`, `services`, `machine`, and `types`.
- `src/kernel/klib/memory/mod.rs` is already the canonical memory facade.

Implication:
- Phase 2 should add a canonical guardrail function in `klib::memory` even if it stays scalar-only for now.
- That seam is enough for later accelerated implementations to use one policy gate instead of scattering ad hoc checks.

### 4. Phase 2 should detect capability but still deny acceleration

Evidence:
- `docs/simd_policy.md` requires machine-state ownership before MMX/SSE/SSE2 execution becomes legal.
- Phase 3 is explicitly the machine-state ownership phase in `.planning/ROADMAP.md`.

Implication:
- Phase 2 runtime policy can legitimately say:
  - CPUID present/absent
  - MMX/SSE/SSE2 supported/unsupported
  - acceleration still forced off
- This keeps capability detection observable without violating the "no SIMD execution yet" rule.

### 5. The test style should mirror existing runtime marker scripts

Evidence:
- `scripts/boot-tests/string-runtime.sh` and `scripts/boot-tests/memory-runtime.sh` validate both source wiring and runtime marker output.
- `scripts/rejection-tests/memory-rejections.sh` uses the existing `KFS_TEST_BAD_*` override pattern to verify failure/short-circuit behavior.
- `scripts/stability-tests/freestanding-simd.sh` already rejects accidental SIMD instructions.

Implication:
- Phase 2 should add a SIMD runtime test script rather than inventing a different proof style.
- Negative/unsupported cases should use arch test toggles rather than special-casing host-only codepaths.

## Recommended Phase Shape

### Plan 02-01
- add arch CPUID helpers
- add core-owned capability/policy logic
- emit observable runtime markers

### Plan 02-02
- add the canonical `klib::memory` guardrail seam
- keep memory helpers scalar-only
- expose the seam through code/tests without introducing new cross-layer imports

### Plan 02-03
- add boot/runtime tests for capability markers and scalar-policy enforcement
- add unsupported-hardware / disabled-policy rejection coverage using the existing arch test-toggle pattern

## Risks

- The repo must not accidentally grow a new linker-visible runtime ABI surface unless that is a deliberate architecture choice.
- CPUID detection must remain safe when CPUID is unavailable; a direct `cpuid` instruction without probing would be wrong for the branch's current compatibility story.
- Tests must not start treating "CPU supports SSE2" as "kernel may execute SSE2"; those remain separate truths until Phase 3.

---
*Phase: 02-capability-detection-runtime-guardrails*
*Researched: 2026-04-05*
