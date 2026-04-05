# Phase 2 Context: Capability Detection & Runtime Guardrails

## Goal

Add CPU capability detection and a canonical runtime policy surface so the kernel can reason about MMX/SSE/SSE2 support without enabling accelerated execution yet.

## Why This Phase Exists

Phase 1 established that future SIMD work must separate:
- CPU capability detection
- runtime legality of executing SIMD instructions
- freestanding/no-host-linkage proofs

Phase 2 exists to add the first two pieces of plumbing without crossing into Phase 3 machine-state enablement or Phase 4 accelerated helper code.

## Current Repo Constraints

- `src/kernel/core/` owns early runtime sequencing and currently runs `run_early_init()` from [`src/kernel/core/init.rs`](/home/motero/Code/kfs-1/src/kernel/core/init.rs).
- `src/kernel/machine/` owns typed low-level primitives and currently exposes only [`src/kernel/machine/port.rs`](/home/motero/Code/kfs-1/src/kernel/machine/port.rs).
- `src/kernel/klib/` owns helper routines and will eventually need a policy seam for scalar-vs-accelerated dispatch.
- `scripts/architecture-tests/layer-dependencies.sh` currently rejects `core -> machine` and `klib -> services/machine` imports, so Phase 2 cannot wire capability detection directly into `core` or future helper leaves without a bridging surface.

## Working Design Direction

The least disruptive seam is:

1. `machine::cpu` owns raw CPUID availability and feature-bit detection.
2. `services::simd` owns runtime-policy initialization and test-mode diagnostics markers.
3. `klib::simd` owns the stored policy/query surface that future helper code can read without importing higher layers.
4. `core::init` calls the service surface during early init, but the resulting policy remains scalar-only until Phase 3 explicitly enables execution legality.

## Non-Goals

- No MMX/SSE/SSE2 instruction execution in kernel helper code yet.
- No CR0/CR4/FXSR/MXCSR ownership yet.
- No accelerated `memcpy`/`memset` yet.
- No CPU baseline increase.

## Acceptance Boundary

Phase 2 is complete only if:
- capability detection exists in a canonical low-level surface
- runtime policy state can be observed without enabling acceleration
- unsupported or forced-disabled cases stay scalar-only
- tests can prove the scalar guardrails and the early-init sequencing
