# Phase 2 Validation

## Quick Checks

Run after each plan:

```bash
node ~/.codex/get-shit-done/bin/gsd-tools.cjs roadmap analyze >/dev/null
```

## Plan-Specific Checks

### Plan 02-01

```bash
cargo_check_unused=0
rg -n "pub mod cpu|pub mod simd|RuntimePolicy|SimdCapabilities" src/kernel/machine src/kernel/klib src/kernel/services
```

### Plan 02-02

```bash
rg -n "initialize_runtime_policy|SIMD_POLICY|SIMD_CPUID" src/kernel/core src/kernel/services src/arch/i386
```

### Plan 02-03

```bash
bash scripts/tests/unit/host-rust-lib.sh tests/host_memory.rs >/dev/null
make test-plain
```

## Full Verification

```bash
make test-plain
```
