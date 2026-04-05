---
phase: 02-capability-detection-runtime-guardrails
plan: 02
subsystem: kernel
tags: [simd, memory, klib, guardrails, scalar-fallback, host-tests]
requires:
  - phase: 02-capability-detection-runtime-guardrails
    provides: canonical SIMD runtime policy and capability detection
provides:
  - canonical `klib::memory` guardrail seam for future accelerated helpers
  - host-visible policy queries without importing `machine` into helper callers
  - scalar-only fallback enforcement through the memory facade
affects: [phase-03-fpu-simd-state, phase-04-accelerated-memory]
tech-stack:
  added: []
  patterns: [facade-reads-policy-not-machine, scalar-fallback-by-default]
key-files:
  created: [tests/host_simd_policy.rs]
  modified: [src/kernel/klib/memory/mod.rs, src/kernel/klib/simd.rs, scripts/tests/unit/simd-policy.sh]
key-decisions:
  - "Future accelerated helper call sites query `klib::memory`, not `machine::cpu`, for policy decisions."
  - "The memory facade exposes read-only guardrails in Phase 2 and does not yet dispatch to accelerated implementations."
patterns-established:
  - "Memory-facing code stays freestanding and policy-driven by reading `klib::simd` through the `klib::memory` facade."
requirements-completed: [COMP-03]
duration: 14min
completed: 2026-04-05
---

# Phase 2 Plan 02 Summary

**A canonical `klib::memory` SIMD guardrail seam with host-visible scalar fallback checks and no machine-layer leakage**

## Performance

- **Duration:** 14 min
- **Started:** 2026-04-05T15:49:40+02:00
- **Completed:** 2026-04-05T16:03:40+02:00
- **Tasks:** 1
- **Files modified:** 4

## Accomplishments

- Added a canonical guardrail seam to `src/kernel/klib/memory/mod.rs` through `simd_policy`, `simd_mode`, and `simd_acceleration_allowed`.
- Added `tests/host_simd_policy.rs` and `scripts/tests/unit/simd-policy.sh` to prove scalar fallback behavior through the real library boundary.
- Kept the memory facade scalar-only while making the future policy hook explicit for Phase 4.

## Task Commits

Each task was committed atomically:

1. **Task 1: Expose the memory-facing guardrail seam and host policy checks** - `f1b0859` (fix)

## Files Created/Modified

- `src/kernel/klib/memory/mod.rs` - Exposes the canonical memory-facing SIMD policy seam for future helpers.
- `src/kernel/klib/simd.rs` - Defines runtime-policy queries consumed by the memory facade.
- `tests/host_simd_policy.rs` - Host tests covering uninitialized, no-CPUID, forced-scalar, runtime-blocked, and no-feature cases.
- `scripts/tests/unit/simd-policy.sh` - Unit/source-level proof entrypoint for the Phase 2 policy seam.

## Decisions Made

- The memory facade is the approved place for helper callers to query acceleration policy; callers must not reach into `machine::cpu`.
- Phase 2 keeps the seam read-only and scalar-only so future accelerated helpers can attach to one decision point without retrofitting call sites.

## Deviations from Plan

### Auto-fixed Issues

**1. [Test architecture alignment] Replaced the planned `host_memory`-only coverage with dedicated SIMD policy host tests**
- **Found during:** Task 1 (memory-facing guardrail seam)
- **Issue:** Extending only `tests/host_memory.rs` would have blurred semantic-memory tests with runtime-policy tests and left the SIMD guardrail contract implicit.
- **Fix:** Added `tests/host_simd_policy.rs` and a dedicated `scripts/tests/unit/simd-policy.sh` runner while keeping `klib::memory` as the public seam.
- **Files modified:** `src/kernel/klib/memory/mod.rs`, `tests/host_simd_policy.rs`, `scripts/tests/unit/simd-policy.sh`
- **Verification:** Dedicated host tests and the umbrella `make test-plain` run passed.
- **Committed in:** `f1b0859`

---

**Total deviations:** 1 auto-fixed (test architecture alignment)
**Impact on plan:** Improved separation of responsibilities; memory semantics and SIMD policy are now tested through clearer boundaries.

## Issues Encountered

The `klib` architecture tests reject device/runtime imports, so the final policy storage remained a simple `static mut` runtime slot instead of introducing atomics in `klib`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 4 now has one approved decision seam for future accelerated helpers, and Phase 3 can refine execution legality without changing memory-facing callers.

---
*Phase: 02-capability-detection-runtime-guardrails*
*Completed: 2026-04-05*
