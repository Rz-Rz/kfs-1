# Phase 1: SIMD Policy & Subject Contract - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase defines the policy and acceptance boundary for optional MMX/SSE/SSE2 work in the existing KFS-1 freestanding kernel. It does not enable SIMD instructions yet; it locks the CPU baseline story, subject-compliance interpretation, ownership boundaries, and verification expectations that later implementation phases must satisfy.

</domain>

<decisions>
## Implementation Decisions

### Policy Shape
- **D-01:** Treat SIMD enablement as optional acceleration layered on top of a required scalar baseline.
- **D-02:** The phase must separate subject compliance, host-linkage concerns, CPU baseline policy, and runtime safety into explicit written rules.
- **D-03:** The branch must not claim that `docs/subject.pdf` forbids SSE/SSE2; the policy must be justified by runtime ownership and toolchain ABI constraints instead.

### Scope Discipline
- **D-04:** Phase 1 is documentation and policy only; no MMX/SSE/SSE2 implementation or compiler-flag enablement belongs here.
- **D-05:** Ownership expectations for future SIMD work must be written before later phases touch `arch`, `machine`, or `klib`.

### the agent's Discretion
- All wording, structure, and file layout choices for the policy/proof docs are at the agent's discretion as long as they stay consistent with repo terminology and the fixed phase boundary.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Subject and architecture contract
- `docs/subject.pdf` — project-level constraints: 32-bit x86, GRUB boot, and no host runtime linkage
- `AGENTS.md` — repo-local architecture, ownership, documentation, and test discipline
- `docs/kernel_architecture.md` — current architecture contract, including the current `i586` Rust baseline note

### Freestanding and toolchain reality
- `docs/m0_2_freestanding_proofs.md` — current no-host-linkage proof strategy
- `Makefile` — current Rust target, linker path, and umbrella test entrypoints
- `scripts/stability-tests/freestanding-simd.sh` — current no-SSE artifact policy gate

### Phase scope
- `.planning/PROJECT.md` — branch-level goal and constraints for SIMD/MMX work
- `.planning/REQUIREMENTS.md` — requirement mapping, especially `COMP-04`
- `.planning/ROADMAP.md` — phase goal and success criteria for Phase 1

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `docs/kernel_architecture.md` already captures current build/runtime boundaries and can host cross-links to a dedicated SIMD policy note.
- `scripts/stability-tests/freestanding-simd.sh` already enforces the current "no accidental XMM/SSE instructions" policy and can anchor future proof strategy language.

### Established Patterns
- Architecture decisions are documented in `docs/` and then enforced by shell tests under `scripts/`.
- The repo keeps freestanding policy in explicit low-level files rather than hidden compiler defaults.

### Integration Points
- New policy/proof notes should live under `docs/`.
- Existing architecture and freestanding proof docs should be updated in the same phase if a dedicated SIMD policy note is added.

</code_context>

<specifics>
## Specific Ideas

- The policy should state clearly that SSE/SSE2 does not imply host linkage.
- The policy should explain the current `i586` workaround and its limitation relative to literal 80386 compatibility.
- The policy should define prerequisites for later MMX/SSE/SSE2 implementation phases.

</specifics>

<deferred>
## Deferred Ideas

- Concrete CPUID feature detection APIs — Phase 2
- CR0/CR4/MXCSR ownership and state management — Phase 3
- Accelerated `memcpy` / `memset` implementation — Phase 4

</deferred>

---
*Phase: 01-simd-policy-subject-contract*
*Context gathered: 2026-04-05*
