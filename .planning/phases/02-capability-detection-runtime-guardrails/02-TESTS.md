# Phase 2 Test Contract

## BDD

Not required for this kernel phase.

## Unit

Required.

Coverage must include:

- pure CPU feature decoding
- unsupported-hardware representation
- scalar fallback policy selection
- installed runtime-policy state through the public crate boundary

Primary surface:

- `tests/host_simd_policy.rs`
- `scripts/tests/unit/simd-policy.sh`

## Integration

Required.

Coverage must include:

- runtime ownership proof for `core -> services::simd`
- runtime marker proof for early-init SIMD policy setup
- rejection proof for bypassed service ownership

Primary surfaces:

- `scripts/architecture-tests/runtime-ownership.sh`
- `scripts/rejection-tests/runtime-ownership-rejections.sh`
- `scripts/boot-tests/runtime-markers.sh`
- `scripts/boot-tests/memory-runtime.sh`

## E2E

Not required beyond the existing umbrella boot pass.

## Final Verification

Phase closeout requires:

```bash
make test-plain
```
