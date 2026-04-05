# Phase 3 Validation Strategy

## Validation Levels

### Quick validation

Use fast checks while iterating on the state-ownership seam:

```bash
bash scripts/tests/unit/simd-policy.sh i386 host-simd-runtime-owned-policy-is-observable
bash scripts/architecture-tests/runtime-ownership.sh i386 core-init-calls-simd-policy-service
```

### Phase validation

Use the Phase 3-targeted proof set before closing the phase:

```bash
bash scripts/boot-tests/simd-policy.sh i386 phase3-runtime-ownership-markers
bash scripts/boot-tests/simd-policy.sh i386 phase3-runtime-ownership-order
bash scripts/rejection-tests/runtime-ownership-rejections.sh i386 core-init-skips-simd-policy-service-fails
bash scripts/stability-tests/freestanding-simd.sh i386 default-freestanding-kernel-limits-approved-simd-state-instructions
```

### Full regression validation

Before phase sign-off:

```bash
make test-plain
```

## Notes

- Phase 3 may introduce approved SIMD control-state instructions, but it must still reject accidental SIMD data-path instructions in freestanding artifacts.
- Runtime ownership remains scalar-first until Phase 4 wires real accelerated helper implementations.

---
*Phase: 03-fpu-mmx-sse-state-ownership*
