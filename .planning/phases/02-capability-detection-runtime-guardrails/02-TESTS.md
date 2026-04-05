# Phase 2 Test Contract

## BDD

Not used for this kernel phase.

## Unit

Required:
- source/unit checks for the canonical `klib::memory` guardrail seam
- host-visible checks that memory helpers remain scalar-safe while the guardrail is disabled

## Integration

Required:
- boot/runtime marker checks for CPUID support and scalar-policy enforcement
- rejection coverage for forced unsupported/disabled SIMD policy cases
- existing freestanding no-SIMD artifact stability checks remain in scope

## E2E

Not required beyond the existing umbrella `make test-plain` run.

## Acceptance Focus

The phase is green only if:
- capability detection is observable
- unsupported or disabled cases stay scalar
- no freestanding artifact begins emitting unconditional SIMD instructions

---
*Phase: 02-capability-detection-runtime-guardrails*
