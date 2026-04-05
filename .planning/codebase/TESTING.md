# Testing Patterns

**Analysis Date:** 2026-04-05

## Test Framework

**Runner:**
- Mixed shell + Rust test stack orchestrated by `make test`
- Top-level shell runner: `scripts/test-host.sh`

**Assertion Library:**
- Rust built-in test harness with `assert!` and `assert_eq!`
- Shell assertions through helper functions and explicit text matching

**Run Commands:**
```bash
make test            # Full repo gate
make test-plain      # Full gate without the optional TUI
make test-vga        # Headless VGA assertion path
make test-qemu       # QEMU boot/runtime checks
bash scripts/stability-tests/freestanding-simd.sh i386 <case>
```

## Test File Organization

**Location:**
- Host Rust tests live in `tests/*.rs`
- Shell verification suites live under `scripts/architecture-tests/`, `scripts/boot-tests/`, `scripts/rejection-tests/`, and `scripts/stability-tests/`

**Naming:**
- Host tests: `host_memory.rs`, `host_string.rs`, `host_vga_writer.rs`
- Shell cases: descriptive kebab-case IDs exposed via `--list`

**Structure:**
```text
tests/
  host_memory.rs
  host_string.rs
  host_vga_writer.rs
scripts/
  architecture-tests/*.sh
  boot-tests/*.sh
  rejection-tests/*.sh
  stability-tests/*.sh
```

## Test Structure

**Suite Organization:**
- Rust tests keep each behavior in a small standalone `#[test]` function
- Shell harnesses expose:
  - `--list` for cases
  - `--description <case>` for descriptions
  - direct `<arch> <case>` execution for targeted runs

**Patterns:**
- Host tests focus on deterministic semantics at the library boundary
- Shell suites verify binary layout, symbol ownership, architecture contracts, and boot/runtime behavior
- Runtime test failures often use marker strings over serial/QEMU exits

## Mocking

**Framework:**
- There is little classic mocking
- Test-specific behavior is usually injected through build/env flags such as `KFS_TEST_FORCE_FAIL`, `KFS_TEST_BAD_LAYOUT`, and similar knobs from `Makefile`

**What to Mock or Simulate:**
- Boot/runtime failure cases via assembly test defines and env vars
- VGA memory and buffer state via host arrays in Rust tests

**What Not to Mock:**
- Shared production module boundaries
- Freestanding artifact structure and linker-visible exports

## Fixtures and Factories

**Test Data:**
- Most Rust tests build simple inline arrays and values
- Shell rejection tests use generated temporary files or deliberately bad source snippets

## Coverage Areas

**Host-Semantic Coverage:**
- `klib` memory/string semantics
- screen/cursor/color/type behavior
- VGA writer and keyboard/VT model behavior

**Artifact/Runtime Coverage:**
- freestanding/no-host-linkage proofs
- boot handoff and `kmain` proofs
- section/layout stability
- architecture ownership and rejection tests

## Coverage Gaps Relevant to SIMD Work

- No current first-class proof that x87 instructions are absent; the existing SIMD gate focuses on XMM/SSE-family instructions
- No current tests for FPU/SSE control-register initialization or save/restore behavior
- No current CPU feature-detection coverage for optional accelerated paths

## Where to Add New SIMD Tests

**Semantic host tests:**
- `tests/host_memory.rs`
- `tests/host_string.rs`

**Freestanding artifact tests:**
- `scripts/stability-tests/freestanding-simd.sh`
- new or extended shell gates for feature policy and state initialization

**Architecture/rejection tests:**
- `scripts/architecture-tests/`
- `scripts/rejection-tests/`

---
*Testing analysis: 2026-04-05*
*Update when test strategy changes*
