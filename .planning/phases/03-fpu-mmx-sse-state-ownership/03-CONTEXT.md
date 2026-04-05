# Phase 3: FPU/MMX/SSE State Ownership - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase owns the machine-state setup required before MMX/SSE/SSE2 instructions can be treated as legal kernel capabilities.

The kernel must:
- initialize the relevant CR0/CR4 and x87/SSE control state during early init
- keep the existing `boot.asm -> kmain -> core::init` handoff unchanged
- define the current execution-boundary contract for a single-task kernel with no task-switch or interrupt save/restore model

This phase does not introduce accelerated `memcpy`/`memset` or integrate SIMD into normal helper paths yet. It makes runtime ownership explicit and observable first.

</domain>

<decisions>
## Implementation Decisions

### Runtime ownership
- **D-01:** Keep raw boot handoff unchanged; SIMD/FPU state ownership begins in early init after `LAYOUT_OK`.
- **D-02:** `machine` owns typed CR0/CR4/x87/MXCSR primitives, `services::simd` owns orchestration, and `core::init` only sequences through the service boundary.
- **D-03:** Phase 3 may initialize runtime state, but the default execution policy remains scalar-only until Phase 4 wires actual accelerated helper implementations.

### Safety contract
- **D-04:** The current kernel is single-task and polling-only, so Phase 3 uses a global ownership model rather than task-switch save/restore.
- **D-05:** Do not implement lazy FPU switching in this phase; clear `TS` and own the state eagerly during early init.
- **D-06:** Keep SSE exceptions masked. `CR4.OSXMMEXCPT` remains out of scope until the kernel owns the relevant exception path.
- **D-07:** If MMX is used in later phases, the contract must require `EMMS` before any return to generic code that may rely on x87 state.

### the agent's Discretion
- Marker naming, helper factoring, and the exact Rust type layout for runtime-state reporting are at the agent's discretion as long as the ownership split and scalar-first execution contract stay explicit.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing branch policy and requirements
- `docs/simd_policy.md` — canonical SIMD policy note from Phases 1-2
- `.planning/REQUIREMENTS.md` — `HW-02`, `HW-04`
- `.planning/ROADMAP.md` — Phase 3 goal and success criteria
- `.planning/phases/02-capability-detection-runtime-guardrails/02-VERIFICATION.md` — verified Phase 2 ownership and guardrail baseline

### Runtime ownership surfaces
- `src/kernel/core/init.rs` — current early-init sequence and marker ordering
- `src/kernel/services/simd.rs` — current Phase 2 orchestration seam
- `src/kernel/machine/cpu.rs` — typed CPUID/MMX/SSE/SSE2 detection
- `src/kernel/klib/simd.rs` — installed runtime policy state
- `src/arch/i386/boot.asm` — minimal boot handoff that must not be bypassed

### Proof and architecture constraints
- `docs/kernel_architecture.md` — current ownership model
- `scripts/architecture-tests/runtime-ownership.sh`
- `scripts/rejection-tests/runtime-ownership-rejections.sh`
- `scripts/stability-tests/freestanding-simd.sh`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/kernel/services/simd.rs` already centralizes SIMD policy installation and boot-marker emission.
- `src/kernel/machine/cpu.rs` already owns typed low-level capability detection and uses inline asm safely inside `machine`.
- `scripts/boot-tests/simd-policy.sh` already proves ordered runtime markers for the SIMD policy seam.

### Established Constraints
- `core` must not import `machine` directly.
- `klib` cannot depend on higher layers or device/runtime modules.
- Phase 2 currently keeps freestanding artifacts on the scalar path and documents that policy in `docs/simd_policy.md`.

### Integration Points
- Early init insertion point is the existing SIMD service call after `LAYOUT_OK`.
- Runtime-state visibility should extend the existing SIMD marker family instead of inventing a separate reporting channel.
- The proof suite should keep using boot, unit, architecture, rejection, and stability scripts rather than introducing a new test framework.

</code_context>

<specifics>
## Specific Ideas

- Add typed machine helpers for CR0/CR4 setup, x87 initialization, and masked SSE control-state initialization.
- Extend the installed runtime policy to record that machine state is owned even while acceleration remains deferred.
- Make the single-task ownership contract explicit in docs and proofs before any accelerated helper implementation lands.

</specifics>

<deferred>
## Deferred Ideas

- `FXSAVE`/`FXRSTOR` task-switch state preservation
- user-mode FP/SIMD ABI handling
- accelerated helper implementations and call-site integration

</deferred>

---
*Phase: 03-fpu-mmx-sse-state-ownership*
*Context gathered: 2026-04-05*
