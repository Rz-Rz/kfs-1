# Kernel, OS, and Rust Review Checks

This reference distills a small set of checks from widely used primary sources:
- OSDev pages on kernel families and monolithic kernels
- xv6 book notes on monolithic vs microkernel organization
- Phil Opp's "Writing an OS in Rust" guidance on encapsulating VGA/hardware access behind modules
- The Rust Book chapter on modules, paths, and privacy

Use these checks when reviewing kernel architecture docs.

## Kernel-family accuracy

- A monolithic kernel can still have strong internal subsystem structure.
- "Monolithic" does not mean "no modules"; it means services and drivers remain in kernel space.
- Do not call a design "hybrid" just because the repo is inconsistent. Inconsistency is not an architecture style.
- Keep the family decision separate from the internal organization decision.

## Boundary review

- Distinguish true external ABI edges from internal language-level boundaries.
- Typical true external edges in a hobby kernel:
  - boot assembly to kernel entry
  - linker-defined symbols
  - firmware or hardware-defined interfaces
- Internal Rust-to-Rust calls should not automatically be treated as ABI contracts unless the project deliberately wants a stable binary surface.

## Rust module review

- Prefer module boundaries, privacy, and `pub` visibility for intra-crate structure.
- Group related definitions by module tree so new code has an obvious home.
- Keep implementation details private by default; promote only deliberate interfaces.
- If a file exists only because the build system compiles it separately, treat that as a build fact, not automatically a sound architecture rule.

## Unsafe and hardware access

- Low-level unsafety should be encapsulated behind narrower interfaces where possible.
- Memory-mapped or port I/O access should not leak through the whole orchestration layer unless required.
- Device-facing details should be concentrated so higher layers depend on capabilities, not register trivia.

## Build and documentation checks

- Any statement that file placement implies architecture must be verified in the build rules.
- If adding a file silently changes linkage behavior, the document should call that out explicitly.
- If the doc proposes enforceable layering, it should say how violations are detected:
  - code review rule
  - tests
  - linting pattern
  - file-role convention

## What to challenge

- Claims that "the subject requires" something the subject does not actually require
- Claims that an internal ABI is necessary when it is merely current practice
- Claims that a shared `types` module should absorb helper logic without a domain reason
- Claims that `kmain` is both a policy layer and a low-level integration layer without acknowledging the tension
