# Phase 3 Test Contract

## BDD

Not used for this kernel phase.

## Unit

Required:
- host-visible policy tests for runtime-owned-but-deferred SIMD state
- source/unit checks for typed machine-state helper presence and policy queries

## Integration

Required:
- boot/runtime marker checks for state-init ordering and runtime ownership
- rejection coverage for bypassing the approved `core -> services -> machine` ownership path
- artifact-level checks that only approved control-state instructions appear after Phase 3

## E2E

Required:
- `make test-plain`

## Acceptance Focus

The phase is green only if:
- early init owns the required machine state before helper self-checks
- the current kernel model explicitly remains global/single-task with no lazy save/restore
- runtime ownership is observable without accidentally enabling data-path SIMD everywhere

---
*Phase: 03-fpu-mmx-sse-state-ownership*
