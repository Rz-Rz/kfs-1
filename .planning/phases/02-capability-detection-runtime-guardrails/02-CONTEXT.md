# Phase 2 Context: Capability Detection & Runtime Guardrails

## Goal

Add the feature-detection and runtime policy hooks that prevent accidental SIMD execution on unsupported paths.

## Why This Phase Exists

Phase 1 established policy and ownership boundaries, but the codebase still has no canonical runtime surface for:

- detecting MMX/SSE/SSE2 capability
- recording whether acceleration is allowed
- giving future helper code a stable scalar fallback decision

Without that surface, later SIMD work would either scatter raw capability checks or bypass the repo's layer rules.

## Current Runtime Shape

Observed early-init path:

1. `src/arch/i386/boot.asm` sets the stack and calls `kmain`
2. `src/kernel/core/entry.rs` owns `kmain`
3. `src/kernel/core/init.rs` runs early validation and helper sanity checks
4. success reaches `console::start_keyboard_echo_loop()`

Current layer constraints matter:

- `core` must not import `machine` directly
- `machine` must remain primitive-only
- `klib` must not depend upward on policy or hardware
- `services` is the only existing seam that can legally orchestrate between `core`, `machine`, and `klib`

## Working Architectural Assumption

Phase 2 will use this split:

- `src/kernel/machine/` for typed CPU feature probing primitives
- `src/kernel/klib/` for durable SIMD policy state and pure selection logic
- `src/kernel/services/` for orchestration that bridges the probe result into installed runtime policy
- `src/kernel/core/init.rs` for sequencing only

That preserves the existing dependency rules while creating a future-safe policy surface for phases 3-5.

## Existing Test Seams

Useful current proof surfaces:

- host Rust unit tests through `scripts/tests/unit/host-rust-lib.sh`
- runtime marker tests in `scripts/boot-tests/runtime-markers.sh`
- memory helper runtime tests in `scripts/boot-tests/memory-runtime.sh`
- runtime ownership architecture tests in `scripts/architecture-tests/runtime-ownership.sh`
- dependency and rejection guards in `scripts/architecture-tests/layer-dependencies.sh` and `scripts/rejection-tests/*`

## Phase Risks

- New policy wiring must not force `core` to import `machine`
- New runtime markers must not destabilize existing ordered-marker tests without updating them in the same change
- Feature detection must stay host-testable without making tests depend on the actual host CPU model
- Docs must be updated in the same change if new ownership paths become canonical
