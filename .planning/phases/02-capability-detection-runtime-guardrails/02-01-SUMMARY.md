---
phase: 02-capability-detection-runtime-guardrails
plan: 01
subsystem: kernel
tags: [simd, mmx, sse, sse2, cpuid, runtime-policy, freestanding]
requires:
  - phase: 01-simd-policy-subject-contract
    provides: canonical SIMD policy and ownership constraints
provides:
  - typed MMX/SSE/SSE2 capability discovery in `machine::cpu`
  - canonical Phase 2 scalar-only runtime policy surface
  - early-init runtime marker emission for CPUID and feature visibility
affects: [phase-02-guardrail-seam, phase-02-proofing, phase-03-fpu-simd-state]
tech-stack:
  added: []
  patterns: [machine-detects-capability, services-install-policy, scalar-first-runtime-guardrails]
key-files:
  created: [src/kernel/machine/cpu.rs, src/kernel/klib/simd.rs, src/kernel/services/simd.rs]
  modified: [src/kernel/core/init.rs, src/kernel/core/entry.rs, src/arch/i386/runtime_io.asm]
key-decisions:
  - "Capability probing belongs in `machine::cpu`, while policy installation belongs in `services::simd`."
  - "Phase 2 may detect MMX/SSE/SSE2 capability, but runtime policy remains scalar-only until Phase 3 owns machine state."
patterns-established:
  - "Typed detection is separated from execution permission so later accelerated code cannot infer safety from raw CPUID bits alone."
requirements-completed: [HW-01, HW-03]
duration: 4min
completed: 2026-04-05
---

# Phase 2 Plan 01 Summary

**Typed CPUID-based SIMD capability discovery with a scalar-only runtime policy installed during early init**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-05T15:39:11+02:00
- **Completed:** 2026-04-05T15:42:57+02:00
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Added `src/kernel/machine/cpu.rs` as the typed MMX/SSE/SSE2 capability probe surface.
- Added canonical Phase 2 runtime-policy state in `src/kernel/klib/simd.rs` and service-level installation/reporting in `src/kernel/services/simd.rs`.
- Wired early init to install the policy and emit runtime markers without permitting accelerated execution.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add typed capability detection and policy seam** - `fe8ffc5` (feat)
2. **Task 2: Wire early-init Phase 2 runtime policy markers** - `0723416` (feat)

## Files Created/Modified

- `src/kernel/machine/cpu.rs` - Owns typed CPUID presence and MMX/SSE/SSE2 capability detection.
- `src/kernel/klib/simd.rs` - Owns canonical runtime-policy state and scalar guardrail queries.
- `src/kernel/services/simd.rs` - Translates machine detection into installed runtime policy plus boot markers.
- `src/kernel/core/init.rs` - Installs the runtime policy during early initialization.
- `src/kernel/core/entry.rs` - Exposes arch-level test toggle wrappers used by early init.
- `src/arch/i386/runtime_io.asm` - Provides test-toggle helpers for forced no-CPUID and forced-disable cases.

## Decisions Made

- Raw feature bits are not treated as execution permission; the runtime policy is the only legal source of "may accelerate" decisions.
- Phase 2 remains scalar even on capable CPUs so the repo does not execute MMX/SSE/SSE2 before Phase 3 owns the control/state model.

## Deviations from Plan

### Auto-fixed Issues

**1. [Architecture alignment] Replaced the planned `core::simd` ownership with the repo-approved `machine` + `services` + `klib` split**
- **Found during:** Task 1 (capability detection and policy seam)
- **Issue:** The original plan text named `src/kernel/core/simd.rs`, but that would have mixed capability probing, policy state, and service orchestration in the wrong layer.
- **Fix:** Landed `machine::cpu` for probing, `services::simd` for installation/markers, and `klib::simd` for canonical guardrail state.
- **Files modified:** `src/kernel/machine/cpu.rs`, `src/kernel/klib/simd.rs`, `src/kernel/services/simd.rs`, `src/kernel/core/init.rs`
- **Verification:** Architecture tests and later full `make test-plain` pass confirmed the ownership split.
- **Committed in:** `fe8ffc5`, `0723416`

---

**Total deviations:** 1 auto-fixed (architecture alignment)
**Impact on plan:** Corrected the ownership model without expanding scope; this made later guardrail and proof work cleaner.

## Issues Encountered

None beyond the ownership adjustment captured above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

The repo now has one canonical place to ask what SIMD capability exists and one canonical policy surface to ask whether acceleration is allowed.
Phase 2 plan 02 can expose that policy through `klib::memory` without leaking machine details into callers.

---
*Phase: 02-capability-detection-runtime-guardrails*
*Completed: 2026-04-05*
