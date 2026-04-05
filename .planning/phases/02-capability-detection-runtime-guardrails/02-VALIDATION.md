# Phase 2 Validation Contract

## Quick Validation

Run the narrow checks needed while iterating on this phase:

```bash
bash scripts/tests/unit/simd-policy.sh i386 host-simd-policy-unit-tests-pass
bash scripts/architecture-tests/runtime-ownership.sh i386 core-init-calls-services-simd
bash scripts/boot-tests/runtime-markers.sh i386 runtime-confirms-simd-policy
```

## Full Validation

Before closing the phase:

```bash
make test-plain
```

## Required Evidence

- host tests prove pure feature decoding and scalar fallback policy
- architecture/rejection tests prove the new service boundary is respected
- boot/runtime tests prove policy setup occurs in early init before memory-helper flow continues
- live docs point to the new canonical ownership paths
