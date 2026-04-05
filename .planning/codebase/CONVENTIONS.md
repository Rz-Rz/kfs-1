# Coding Conventions

**Analysis Date:** 2026-04-05

## Naming Patterns

**Files:**
- Rust source uses snake_case leaf names with `mod.rs` directory roots
- Host test files use `host_*.rs`
- Shell scripts are descriptive and task-oriented, usually `kebab-case.sh` or domain-specific names

**Functions:**
- Rust functions are snake_case
- Exported freestanding ABI symbols use explicit kernel-prefixed names such as `kfs_memcpy`, `kfs_memset`, and `kmain`
- Test case IDs in shell scripts are long, descriptive kebab-case strings

**Variables:**
- Rust locals and fields are snake_case
- Shell variables are usually `UPPER_SNAKE_CASE` for environment/config and snake_case for locals
- Build knobs use `KFS_*` env vars

**Types:**
- Rust types use PascalCase such as `KernelRange`, `CursorPos`, and `Port`
- Constants use `UPPER_SNAKE_CASE`

## Code Style

**Formatting:**
- Rust code follows standard rustfmt-style formatting
- Python tooling is configured with Black/Ruff at 100 columns in `pyproject.toml`
- Bash scripts use tabs/indentation pragmatically but keep one assertion/helper per block

**Linting:**
- `make test` runs lint unless `KFS_SKIP_LINT=1`
- `scripts/lint.sh` is the top-level lint entrypoint

## Import Organization

**Order:**
1. crate-local imports such as `use crate::kernel::...`
2. `core` imports
3. external items only where unavoidable in host tooling

**Grouping:**
- Rust imports are grouped compactly; the codebase does not prefer large blank-separated import blocks

**Path Rules:**
- Host tests must import the real crate API through `kfs::kernel::...`
- Do not use `#[path = "../src/..."]` or `include!("../src/...")` for production code in tests

## Error Handling

**Patterns:**
- Freestanding runtime favors explicit failure markers and hard-stop behavior over rich recovery
- Host tests use `assert_eq!`, `assert!`, and direct semantic checks
- Shell harnesses centralize `die()` helpers and non-zero exits

**Error Types:**
- Early init uses enum-driven failure classification in `src/kernel/core/init.rs`
- Panic handling is centralized in `src/freestanding/panic.rs`

## Logging

**Framework:**
- No logging framework
- Diagnostics use serial/text markers through the runtime path and shell harnesses

**Patterns:**
- Log/proof markers are explicit strings used by tests
- Build/test scripts print deterministic PASS/FAIL style output

## Comments

**When to Comment:**
- Comments explain boot/linker invariants, ownership constraints, or non-obvious low-level behavior
- Avoid redundant commentary in simple helper code

**TODO Comments:**
- No dominant TODO format is enforced in the analyzed files
- Planning/debt is more often captured in docs or test cases than inline TODO clutter

## Function Design

**Size:**
- Leaf functions are generally small and focused
- Shared semantics are extracted into helpers rather than duplicated between freestanding and host paths

**Parameters:**
- Low-level helpers pass raw pointers/lengths or small domain structs directly
- Public helper APIs mirror C-style signatures where ABI stability matters

**Return Values:**
- Guard clauses and explicit returns are common
- Unsafe helpers often return original destination pointers to mimic libc-style contracts

## Module Design

**Exports:**
- Public surfaces live in the owning module root
- Private implementation details often sit in `imp.rs` leafs behind a stable facade

**Ownership Rules:**
- `src/kernel/mod.rs` is the only shared module root
- `src/freestanding/` is freestanding-only
- `arch` and `machine` are the only acceptable homes for inline assembly

## Testing Expectations

- Keep tests with the behavior they prove
- Update docs/test guidance in the same change when ownership or paths move
- Prefer `make test` as the umbrella verification command

---
*Convention analysis: 2026-04-05*
*Update when style or architecture rules change*
