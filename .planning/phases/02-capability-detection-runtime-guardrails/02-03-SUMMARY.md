---
phase: 02-capability-detection-runtime-guardrails
plan: 03
subsystem: testing
tags: [simd, boot-tests, rejection-tests, architecture-tests, scalar-policy, proofs]
requires:
  - phase: 02-capability-detection-runtime-guardrails
    provides: observable runtime policy markers and canonical guardrail seam
provides:
  - boot/runtime proofs for Phase 2 SIMD policy markers
  - rejection and architecture guards against layer bypasses
  - preserved no-SIMD freestanding artifact checks during the policy-only phase
affects: [phase-03-fpu-simd-state, phase-05-proof-hardening]
tech-stack:
  added: []
  patterns: [boot-proofs-for-policy, rejection-tests-for-layer-bypasses, no-simd-artifact-enforcement]
key-files:
  created: [scripts/boot-tests/simd-policy.sh, scripts/tests/unit/simd-policy.sh]
  modified: [scripts/architecture-tests/runtime-ownership.sh, scripts/rejection-tests/runtime-ownership-rejections.sh, docs/kernel_architecture.md, docs/simd_policy.md]
key-decisions:
  - "Phase 2 proofs assert observable policy markers and scalar fallback, not accelerated execution."
  - "SIMD ownership rejection cases belong in the existing runtime-ownership proof family rather than a parallel ad hoc test tree."
patterns-established:
  - "Capability-policy work must land with observable boot markers, source-level ownership guards, and preserved freestanding artifact checks."
requirements-completed: [COMP-03, HW-03]
duration: 21min
completed: 2026-04-05
---

# Phase 2 Plan 03 Summary

**Boot, rejection, and architecture proofs that make Phase 2 SIMD policy observable while preserving the no-SIMD freestanding artifact contract**

## Performance

- **Duration:** 21 min
- **Started:** 2026-04-05T15:42:57+02:00
- **Completed:** 2026-04-05T16:03:40+02:00
- **Tasks:** 1
- **Files modified:** 9

## Accomplishments

- Added `scripts/boot-tests/simd-policy.sh` to assert runtime markers, ordering, forced no-CPUID, and forced scalar-disable behavior.
- Extended architecture and rejection tests so `core::init` must route SIMD policy through services instead of importing `machine` directly.
- Preserved the existing freestanding no-SIMD artifact policy and aligned the live docs to the landed ownership model.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add policy proofs and align ownership tests/docs** - `f1b0859` (fix)

## Files Created/Modified

- `scripts/boot-tests/simd-policy.sh` - Boot/runtime checks for marker presence, ordering, no-CPUID, and forced-disable cases.
- `scripts/architecture-tests/runtime-ownership.sh` - Architecture proof that `core::init` installs policy through `services::simd`.
- `scripts/rejection-tests/runtime-ownership-rejections.sh` - Rejection proof that direct `machine::cpu` policy usage in core is forbidden.
- `scripts/tests/unit/simd-policy.sh` - Unit/source policy checks used by the umbrella suite.
- `docs/kernel_architecture.md` - Documents the final `machine` / `services` / `klib` ownership split.
- `docs/simd_policy.md` - Records the current Phase 2 realization and scalar-only runtime boundary.

## Decisions Made

- Runtime policy proofs were named around "policy" rather than "runtime" because the phase is about observability and scalar enforcement, not accelerated execution.
- Ownership enforcement was merged into the existing runtime-ownership proof family to avoid a second overlapping architecture-test hierarchy.

## Deviations from Plan

### Auto-fixed Issues

**1. [Proof structure alignment] Replaced the planned standalone `simd-runtime-rejections` family with integrated ownership and policy proofs**
- **Found during:** Task 1 (proof hardening)
- **Issue:** A separate `simd-runtime-rejections.sh` family would have duplicated the repo's established runtime-ownership proof structure and missed the real architectural risk, which was bypassing `services::simd`.
- **Fix:** Added `scripts/boot-tests/simd-policy.sh`, extended `scripts/architecture-tests/runtime-ownership.sh`, and extended `scripts/rejection-tests/runtime-ownership-rejections.sh`.
- **Files modified:** `scripts/boot-tests/simd-policy.sh`, `scripts/architecture-tests/runtime-ownership.sh`, `scripts/rejection-tests/runtime-ownership-rejections.sh`
- **Verification:** Targeted proof scripts and the umbrella `make test-plain` pass succeeded.
- **Committed in:** `f1b0859`

---

**Total deviations:** 1 auto-fixed (proof structure alignment)
**Impact on plan:** Reduced duplication and made the proof suite enforce the real layer boundary instead of only naming SIMD cases.

## Issues Encountered

The first ownership pass left an `extern "C"` contract in `machine::cpu` and attempted atomics in `klib::simd`; both were corrected so the architecture tests passed under the repo's existing layer rules.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 3 can now assume the repo has observable pre-acceleration policy proofs, stable scalar fallback behavior, and enforced ownership boundaries before any FPU/MMX/SSE control-state work begins.

---
*Phase: 02-capability-detection-runtime-guardrails*
*Completed: 2026-04-05*
