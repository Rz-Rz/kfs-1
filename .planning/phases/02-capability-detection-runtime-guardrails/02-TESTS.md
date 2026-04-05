# Phase 2 Test Contract

## BDD

Not required.

## Unit / Host Tests

Required:
- host tests for pure capability parsing and runtime-policy semantics
- host tests proving forced scalar-only policy remains false for MMX/SSE/SSE2 execution

Likely files:
- `tests/host_simd_policy.rs`
- updates to `tests/host_memory.rs` if policy-facing helper seams are added there

## Integration / Architecture Tests

Required:
- architecture/runtime-ownership test proving early init reaches the new SIMD policy initialization seam
- architecture/layer checks proving the new files stay in allowed ownership boundaries

Likely files:
- `scripts/architecture-tests/runtime-ownership.sh`
- `scripts/rejection-tests/runtime-ownership-rejections.sh`

## Boot / Runtime Tests

Required:
- deterministic runtime-marker coverage for policy initialization
- forced `no cpuid` and forced `disable simd` cases that still remain scalar-only

Likely files:
- `scripts/boot-tests/`
- `scripts/rejection-tests/`

## Stability Tests

Required:
- existing `scripts/stability-tests/freestanding-simd.sh` must keep passing because Phase 2 still enables no actual SIMD execution

## End-to-End

Not required beyond `make test-plain`.
