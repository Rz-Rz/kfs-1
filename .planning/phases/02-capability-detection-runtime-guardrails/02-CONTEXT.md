# Phase 2: Capability Detection & Runtime Guardrails - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase introduces the first code for SIMD/MMX/SSE2 awareness, but it is still not an enablement phase.

The kernel must:
- detect whether CPUID and the relevant feature bits exist
- record a canonical runtime policy for optional acceleration
- keep the actual memory/helper behavior scalar-only until Phase 3 owns FPU/MMX/SSE machine state

This phase does not execute SIMD instructions in freestanding kernel code.

</domain>

<decisions>
## Implementation Decisions

### Architectural shape
- **D-01:** Preserve the current `start -> kmain -> core::init` handoff with no new boot bypasses.
- **D-02:** Keep low-level CPUID access at the existing `arch runtime helper -> core entry` ABI boundary instead of introducing a new `core -> machine` dependency in this phase.
- **D-03:** Keep `klib` scalar by default; the Phase 2 guardrail seam exists so later accelerated helpers have one canonical decision point.

### Runtime policy
- **D-04:** Capability detection and acceleration permission are different truths. Phase 2 may observe CPU support while still forcing scalar behavior.
- **D-05:** Unsupported hardware or policy-disabled paths must succeed by staying scalar, not by failing boot.
- **D-06:** Runtime markers should make CPUID/capability/policy state observable in test mode without creating a fake parallel codepath.

### the agent's Discretion
- Marker naming, internal type layout, and helper factoring are at the agent's discretion as long as they remain consistent with Phase 1 policy and repo architecture rules.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Branch policy and requirements
- `docs/simd_policy.md` — canonical Phase 1 policy note, especially ownership boundaries and proof obligations
- `.planning/REQUIREMENTS.md` — `COMP-03`, `HW-01`, `HW-03`
- `.planning/ROADMAP.md` — Phase 2 goal and success criteria

### Runtime ownership and current code
- `src/arch/i386/boot.asm` — current start -> `kmain` handoff
- `src/arch/i386/runtime_io.asm` — existing arch runtime helper surface and test-toggle pattern
- `src/kernel/core/entry.rs` — current arch helper extern block and runtime fail behavior
- `src/kernel/core/init.rs` — current early-init sequencing and diagnostic markers
- `src/kernel/klib/memory/mod.rs` — future acceleration seam for memory helpers

### Enforcement and test surfaces
- `scripts/architecture-tests/runtime-ownership.sh`
- `scripts/architecture-tests/layer-dependencies.sh`
- `scripts/boot-tests/memory-runtime.sh`
- `scripts/rejection-tests/memory-rejections.sh`
- `scripts/stability-tests/freestanding-simd.sh`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/arch/i386/runtime_io.asm` already hosts arch-owned test toggles and runtime helpers such as `kfs_arch_is_test_mode` and `kfs_arch_qemu_exit`.
- `src/kernel/core/entry.rs` already owns the extern ABI boundary to arch runtime helpers.
- `src/kernel/core/init.rs` already emits ordered diagnostic markers during test-mode early init.
- `src/kernel/klib/memory/mod.rs` is the canonical future ownership point for memory acceleration.

### Established Constraints
- `core` must not import `machine` directly under current layer-dependency enforcement.
- `klib` must not import higher-level modules, so any future acceleration gate must be reachable without `klib -> core/services/machine` imports.
- `scripts/stability-tests/freestanding-simd.sh` already rejects accidental SIMD instruction emission in freestanding artifacts.

### Integration Points
- New CPUID helpers can extend `src/arch/i386/runtime_io.asm` without changing boot ownership.
- New runtime policy logic belongs in `src/kernel/core/`.
- The guardrail seam for future accelerated helpers belongs in `src/kernel/klib/memory/`.

</code_context>

<specifics>
## Specific Ideas

- Add arch helpers for CPUID support and leaf-1 feature bits using the existing `kfs_arch_*` pattern.
- Add a `core::simd` policy module that can emit test-mode markers such as CPUID support, MMX/SSE/SSE2 capability, and scalar-policy enforcement.
- Add a canonical `klib::memory` guardrail function even if it remains false in Phase 2.

</specifics>

<deferred>
## Deferred Ideas

- CR0/CR4/FXSR/SSE machine-state initialization — Phase 3
- Any actual MMX/SSE/SSE2 memory implementation — Phase 4
- Integration of accelerated paths into normal kernel callsites — Phase 5

</deferred>

---
*Phase: 02-capability-detection-runtime-guardrails*
*Context gathered: 2026-04-05*
