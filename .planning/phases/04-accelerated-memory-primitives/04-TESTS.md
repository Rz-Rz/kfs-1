# Phase 4 Test Contract

## BDD

Not used for this kernel phase.

## Unit

Required:
- host semantic tests for scalar `memcpy` and `memset`
- host-visible backend-selection tests for uninitialized, blocked, forced-scalar, and deferred policies
- source/unit checks that the memory facade owns dispatch and keeps exports in `mod.rs`

## Integration

Required:
- boot/runtime marker checks for selected `memcpy` and `memset` backends during early-init sanity paths
- ordering checks that backend markers precede helper-success markers
- architecture checks that backend selection remains inside `klib::memory` and does not bypass the approved layer path

## E2E

Required:
- `make test-plain`

## Acceptance Focus

The phase is green only if:
- memory helper semantics remain unchanged
- the kernel can prove which backend it selected for each helper
- unsupported or not-yet-implemented acceleration paths fall back to scalar explicitly and observably

---
*Phase: 04-accelerated-memory-primitives*
