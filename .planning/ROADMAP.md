# Roadmap: KFS-1 SIMD/MMX Enablement

## Overview

This roadmap adds optional MMX/SSE/SSE2 acceleration to the existing freestanding kernel in the only safe order that makes sense for this repo: policy first, then feature detection and machine-state ownership, then accelerated primitives, then integration and proof hardening. The milestone is successful only if performance-oriented changes preserve GRUB bootability, freestanding linkage, and the repo's architecture discipline.

## Phases

- [x] **Phase 1: SIMD Policy & Subject Contract** - define CPU baseline, subject interpretation, and acceptance boundaries for SIMD work (completed 2026-04-05)
- [ ] **Phase 2: Capability Detection & Runtime Guardrails** - introduce explicit feature policy before any accelerated path can execute
- [ ] **Phase 3: FPU/MMX/SSE State Ownership** - add the machine-state initialization and preservation model required for safe SIMD use
- [ ] **Phase 4: Accelerated Memory Primitives** - implement optional accelerated helper routines with scalar fallback
- [ ] **Phase 5: Kernel Integration & Proof Hardening** - wire accelerated paths selectively and extend artifact/runtime tests
- [ ] **Phase 6: Documentation & Future Expansion** - finish sign-off docs and define post-v1 SIMD follow-on work

## Phase Details

### Phase 1: SIMD Policy & Subject Contract
**Goal**: Establish the supported CPU/feature policy, subject-compliance interpretation, and exact acceptance criteria for MMX/SSE/SSE2 work.
**Depends on**: Nothing (first phase)
**Requirements**: [COMP-04]
**Success Criteria** (what must be TRUE):
  1. The branch has a written policy for CPU baseline, optional acceleration, and fallback behavior.
  2. The repo's subject/no-host-linkage constraints are translated into concrete acceptance criteria for SIMD work.
  3. Open design risks are recorded before implementation begins.
**Plans**: 3 plans

Plans:
- [x] 01-01: consolidate subject, ABI, and current toolchain constraints into a single SIMD policy note
- [x] 01-02: define allowed ownership boundaries for SIMD-related arch, machine, and klib code
- [x] 01-03: define the verification strategy that later phases must satisfy

### Phase 2: Capability Detection & Runtime Guardrails
**Goal**: Add the feature-detection and runtime policy hooks that prevent accidental SIMD execution on unsupported paths.
**Depends on**: Phase 1
**Requirements**: [COMP-03, HW-01, HW-03]
**Success Criteria** (what must be TRUE):
  1. The kernel can distinguish whether optional MMX/SSE/SSE2 acceleration is allowed.
  2. Unsupported hardware or disabled policy paths stay on the scalar implementation.
  3. Tests can observe and reject illegal entry into accelerated paths.
**Plans**: 3 plans

Plans:
- [ ] 02-01: add CPU feature discovery and a canonical runtime policy surface
- [ ] 02-02: expose guardrails to klib and future call sites without leaking architecture shortcuts
- [ ] 02-03: add tests and rejection cases for unsupported or disabled SIMD paths

### Phase 3: FPU/MMX/SSE State Ownership
**Goal**: Own the machine-state setup needed before MMX/SSE/SSE2 instructions are legal in kernel code.
**Depends on**: Phase 2
**Requirements**: [HW-02, HW-04]
**Success Criteria** (what must be TRUE):
  1. Early runtime initializes the required machine state before accelerated routines are reachable.
  2. The kernel has a documented policy for preserving or constraining FP/SIMD state across execution boundaries.
  3. MMX-specific cleanup requirements and SSE control-state expectations are explicit.
**Plans**: 3 plans

Plans:
- [ ] 03-01: implement/control-register setup and early-init sequencing for FP/SIMD enablement
- [ ] 03-02: define save/restore or execution-boundary constraints appropriate to the current kernel model
- [ ] 03-03: add low-level proofs for init ordering and forbidden pre-init use

### Phase 4: Accelerated Memory Primitives
**Goal**: Introduce optional accelerated `memcpy` and `memset` implementations with semantic parity to the existing scalar routines.
**Depends on**: Phase 3
**Requirements**: [ACC-01, ACC-02, ACC-03, VER-01]
**Success Criteria** (what must be TRUE):
  1. `memcpy` and `memset` preserve current semantics regardless of whether acceleration is enabled.
  2. Accelerated code lives in approved ownership boundaries.
  3. Host tests and targeted kernel proofs distinguish scalar and accelerated execution safely.
**Plans**: 3 plans

Plans:
- [ ] 04-01: define the canonical module/facade shape for accelerated helper routines
- [ ] 04-02: implement optional accelerated `memcpy`
- [ ] 04-03: implement optional accelerated `memset` and host semantic parity tests

### Phase 5: Kernel Integration & Proof Hardening
**Goal**: Integrate accelerated primitives into selected kernel paths and strengthen freestanding, boot, and architecture proofs.
**Depends on**: Phase 4
**Requirements**: [COMP-01, COMP-02, VER-02, VER-03, VER-04]
**Success Criteria** (what must be TRUE):
  1. The kernel still boots and passes freestanding/no-host-linkage checks.
  2. Accidental unconditional SIMD emission is caught by stability tests.
  3. Architecture/rejection tests guard the approved SIMD ownership model.
**Plans**: 3 plans

Plans:
- [ ] 05-01: integrate accelerated primitives into selected kernel call sites with clear fallbacks
- [ ] 05-02: extend stability and boot proofs for subject compliance after SIMD work
- [ ] 05-03: extend architecture and rejection tests for SIMD boundaries

### Phase 6: Documentation & Future Expansion
**Goal**: Close the milestone with aligned docs and a clear backlog for post-v1 accelerations.
**Depends on**: Phase 5
**Requirements**: [COMP-04]
**Success Criteria** (what must be TRUE):
  1. Live docs explain the final SIMD policy, limitations, and verification story.
  2. The next worthwhile acceleration targets are captured without polluting v1 scope.
  3. The branch can transition cleanly into phased execution work.
**Plans**: 2 plans

Plans:
- [ ] 06-01: update architecture/proof/docs to reflect the landed SIMD policy
- [ ] 06-02: capture post-v1 candidates such as string or VGA-path acceleration

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. SIMD Policy & Subject Contract | 3/3 | Complete    | 2026-04-05 |
| 2. Capability Detection & Runtime Guardrails | 0/3 | Not started | - |
| 3. FPU/MMX/SSE State Ownership | 0/3 | Not started | - |
| 4. Accelerated Memory Primitives | 0/3 | Not started | - |
| 5. Kernel Integration & Proof Hardening | 0/3 | Not started | - |
| 6. Documentation & Future Expansion | 0/2 | Not started | - |
