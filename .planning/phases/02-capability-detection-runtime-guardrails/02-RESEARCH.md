# Phase 2 Research: Capability Detection & Runtime Guardrails

## Key Findings

### 1. `services` is the correct orchestration seam

Evidence:

- `src/kernel/core/init.rs` already imports `services` and `klib`
- `scripts/architecture-tests/layer-dependencies.sh` forbids `core` importing `machine`
- the same script does not forbid `services` from importing `machine` or `klib`

Consequence:

- `core` should sequence SIMD policy installation through a new `services` facade
- `machine` should not be imported directly into `core`

### 2. Current runtime tests already rely on ordered diagnostics markers

Evidence:

- `scripts/boot-tests/runtime-markers.sh` checks `KMAIN_OK -> BSS_OK -> LAYOUT_OK -> EARLY_INIT_OK -> KMAIN_FLOW_OK`
- `scripts/boot-tests/memory-runtime.sh` checks `MEMCPY_OK -> MEMSET_OK -> MEMORY_HELPERS_OK`
- `scripts/rejection-tests/runtime-init-rejections.sh` proves failures stop later markers from appearing

Consequence:

- Phase 2 can add deterministic policy markers, but must update ordered-marker expectations in the same change

### 3. Existing negative-runtime pattern is compile-time test override via NASM flags

Evidence:

- `src/arch/i386/runtime_io.asm` exposes `kfs_arch_should_fail_*` helpers
- `Makefile` drives them through `TEST_ASM_DEFS`
- rejection suites use env toggles such as `KFS_TEST_BAD_LAYOUT=1`

Consequence:

- if Phase 2 needs deterministic negative runtime paths, the existing pattern is available
- but host tests should carry most capability-matrix coverage so runtime tests do not depend on the actual CPU model

### 4. Host tests need pure policy helpers, not live CPUID dependence

Evidence:

- `scripts/tests/unit/host-rust-lib.sh` compiles the real `src/lib.rs` library and runs pure Rust tests
- `tests/host_memory.rs` shows the preferred style: test pure contract behavior through the real crate API

Consequence:

- CPU-feature decoding and policy-selection logic should be pure functions
- actual machine probing should be wrapped so host tests can validate logic without asserting the host machine's features

### 5. New ownership paths will need architecture and docs updates

Evidence:

- `docs/simd_policy.md` says `machine` owns typed low-level machine primitives, `klib` owns helper dispatch, and `docs`/`scripts` own proof harnesses
- repo rules require docs and guidance updates when canonical ownership changes

Consequence:

- if Phase 2 lands `machine::cpu`, `klib::simd`, and `services::simd`, live docs must mention them

## Recommended Implementation Shape

### Machine layer

Add `src/kernel/machine/cpu.rs` with:

- typed CPU feature struct(s)
- pure decoding from raw feature bits
- actual runtime probe function

### Klib layer

Add `src/kernel/klib/simd.rs` with:

- pure policy selection logic
- installed runtime-policy state
- future-facing query surface for accelerated helpers

### Services layer

Add `src/kernel/services/simd.rs` with:

- orchestration that probes machine features
- installs scalar-safe policy into `klib`
- exposes a small result surface to `core::init`

### Core sequencing

`src/kernel/core/init.rs` should:

- call the service-layer SIMD initializer before memory-helper sanity checks
- emit deterministic test markers around successful policy installation
- keep failure ownership in the existing early-init error path

## Test Strategy

- Host tests: decode matrix, policy selection, installed scalar fallback
- Architecture tests: core delegates via `services::simd`, machine remains primitive-only
- Boot tests: runtime emits SIMD policy markers in a stable order
- Rejection tests: missing service delegation or bypassed layer boundaries fail
