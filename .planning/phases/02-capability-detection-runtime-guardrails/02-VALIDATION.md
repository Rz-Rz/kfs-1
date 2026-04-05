# Phase 2 Validation Strategy

## Validation Levels

### Quick validation

Use fast checks while iterating on the capability/policy seam:

```bash
node ~/.codex/get-shit-done/bin/gsd-tools.cjs roadmap analyze >/dev/null
bash scripts/tests/unit/memory-helpers.sh i386 host-memcpy-unit-tests-pass
```

### Phase validation

Use the Phase 2-targeted proof set before closing the phase:

```bash
bash scripts/boot-tests/simd-runtime.sh i386 runtime-confirms-scalar-policy
bash scripts/rejection-tests/simd-runtime-rejections.sh i386 forced-no-cpuid-stays-scalar
bash scripts/stability-tests/freestanding-simd.sh i386 default-freestanding-kernel-disables-simd-instructions
```

### Full regression validation

Before phase sign-off:

```bash
make test-plain
```

## Notes

- `make test-plain` remains the canonical umbrella proof and must pass before the phase is declared complete.
- Phase 2 should not relax the existing no-SIMD artifact checks; they remain valid because acceleration is still disabled.

---
*Phase: 02-capability-detection-runtime-guardrails*
