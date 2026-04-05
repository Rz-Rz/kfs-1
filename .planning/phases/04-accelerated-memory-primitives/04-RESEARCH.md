# Phase 4 Research Notes

## Summary

Phase 4 should start by separating three concerns that were previously collapsed into a single scalar implementation:

1. Semantic contract
- `memcpy` and `memset` semantics remain defined by the existing scalar byte-loop behavior.

2. Dispatch contract
- the memory family decides which backend executes based on installed runtime policy plus backend availability
- callers do not choose instruction families directly

3. Proof contract
- host tests prove semantics and selection behavior
- boot tests prove which backend the kernel selected during early-init sanity checks
- artifact tests stay conservative until real SIMD data-path instructions are introduced intentionally

## Recommended backend order

- `Scalar` is always available.
- `SSE2` is the preferred first optimized tier for this branch.
- `MMX` is optional and deferred because it adds cleanup complexity (`EMMS`) for weaker long-term payoff.

## Phase 4 implementation order

1. Create the canonical dispatch/facade shape and runtime-visible backend markers.
2. Add a real `memcpy` optimized backend and update the selector plus proofs.
3. Add a real `memset` optimized backend and parity tests.

## Main risk

Allowing new SIMD instructions into the freestanding kernel artifact before the dispatch boundary and proof surface exist would make regressions harder to reason about. The safe order is dispatch first, data-path second.

---
*Phase: 04-accelerated-memory-primitives*
