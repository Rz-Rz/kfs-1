# Kernel Architecture Rules

This repo has two intentional Rust crate roots:

- `src/main.rs`: freestanding kernel root
- `src/lib.rs`: host-testable library root

Both roots must share the same subsystem tree through `src/kernel/mod.rs`. Do not create a second shared-root file or a parallel module tree.

## Entry And Ownership

- The freestanding entry symbol remains `#[no_mangle] extern "C" fn kmain() -> !`.
- The canonical entry implementation lives in `src/kernel/core/entry.rs`.
- Boot ASM hands off only to `kmain`.
- Early runtime validation and the first helper sanity path live in `src/kernel/core/init.rs`.

## Host-Test Architecture

- Host tests must import the real crate API through `kfs::kernel::...`.
- Host unit scripts must link `src/lib.rs` as a real library boundary.
- Do not mount production source into tests with `#[path = "../src/..."]`.
- Do not use `include!("../src/...")` to compile production files inside tests.
- Do not compile host tests as isolated fake-root crates when they should link the shared library.

## Anti-Bypass Rules

- Do not use `#[cfg(test)]` or feature-gated import switching to pick different module paths for the same responsibility.
- Do not add test-only aliases, duplicate module trees, or shim definitions to hide architectural drift.
- If code is hard to test, extract or expose the production module boundary instead of teaching the file about the test harness.
- There must be one canonical definition and one canonical access path per responsibility.

## Shared Module Layout

- Shared subsystem wiring belongs in `src/kernel/mod.rs`.
- Helper families live under `src/kernel/klib/`.
- Type/layout definitions live under `src/kernel/types/`.
- Port I/O ownership lives under `src/kernel/machine/`.
- VGA text driver ownership lives under `src/kernel/drivers/vga_text/`.
- Service-level console wiring lives under `src/kernel/services/console.rs`.

## Documentation Discipline

- When canonical ownership or paths change, update docs and test guidance in the same change.
- Do not leave references to deleted kernel paths or superseded module layouts in live docs, scripts, or guidance.

## Test Build Contract

- `Makefile` is the canonical owner of compilation, linking, packaging, and proof artifact creation.
- Test scripts may launch cases and assert outcomes, but they must not become alternate build systems.
- Shared boot/test artifacts belong behind `make test-prep` and `make test-artifacts`.
- Host Rust unit tests must build through `make host-rust-test`, linking the real `src/lib.rs` crate boundary.
- Rejection, stability, and proof checks should consume Makefile-owned stamp targets or named artifacts rather than rebuilding ad hoc inside the script.
- Do not add script-side `rustc`, `ld`, `nasm`, `make clean`, or `make -B all` paths for production or proof coverage when the same artifact can be owned by `Makefile`.
- If a new test needs a special artifact, add a named Makefile target or stamp for it and have the script call or consume that target.

## Test Runner Separation

- Scripts own `--list`, `--description`, case selection, and assertions on logs, symbols, sections, or runtime behavior.
- `scripts/test-host.sh` owns scheduling and parallel execution policy.
- Workspace-mutating or artifact-heavy cases should run in worker workspaces through the existing heavy-worker path.
- Host unit cases that stay in the main workspace must use unique output paths per case or filter to avoid parallel collisions.
- Do not serialize the whole suite to hide shared-output bugs; fix the artifact ownership or naming instead.

## TUI Contract

- The TUI is a presentation layer over the same runner contract used by plain `make test`.
- `make test` and `make test-ui` must drive the same underlying `scripts/test-host.sh` case graph.
- The TUI must not own compile logic, artifact generation, or a separate test manifest format.
- If the TUI needs more information, extend the runner protocol or manifest emitted by the existing runner instead of adding a second execution path.

## Test Command Discipline

- Use plain `make test` as the umbrella verification command for this repo.
- Do not run `make test arch=...`.
- If narrower debugging is needed, use the specific test script or target directly rather than changing the umbrella `make test` invocation.
- Narrow tests are for debugging only; they do not replace a final `make test` run.
- Do not treat an older green `make test` run as valid after new edits have been made.
- After any code, test, build, boot, or TUI change, rerun `make test` on the current diff before committing.
- Do not commit functional changes while `make test` is red or unverified for the current diff.
- If `make test` fails at any point after the latest edits, keep the work uncommitted until `make test` is green again.
- Exception: the repo owner may explicitly override the commit/push gate for the current change by directly instructing the agent to commit and/or push despite a red or unverified `make test` run.
