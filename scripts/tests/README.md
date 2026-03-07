# Test Framework Notes

This directory is part of the shell-based test framework used by `scripts/test-host.sh`.

The current philosophy is:

- One listed test case should prove one behavior.
- Test case names should describe the behavior being checked.
- Script file names should describe the area under test.
- Do not use redundant prefixes like `check-` or `test-` in user-facing script names when the directory already tells you it is a test.

This document exists mainly to make rebases easier for branches that still use the older naming and grouping.

## Directory Layout

The host runner currently executes these sections:

- `scripts/tests/`
- `scripts/stability-tests/`
- `scripts/rejection-tests/`
- `scripts/boot-tests/`

Each section is a directory of executable `.sh` files. The section headers shown by `scripts/test-host.sh` are hardcoded there.

## Discovery Contract

For a script to be discoverable by `scripts/test-host.sh`, it must:

1. Live in one of the section directories above.
2. Be a `.sh` file.
3. Support `--list` and print one case id per line.
4. Support `--description <case>` and print a human-readable description.
5. Support normal execution as:

```bash
bash path/to/script.sh <arch> <case>
```

The host runner does this:

1. Finds `*.sh` files in the section directory.
2. Calls each script with `--list`.
3. Calls each script with `--description <case>`.
4. Runs each discovered case independently.

That means the real unit of discovery is the listed case, not the script file.

## Naming Rules

### Script names

Prefer names like:

- `kernel-sections.sh`
- `section-stability.sh`
- `freestanding-kernel.sh`
- `qemu-boot.sh`

Avoid names like:

- `check-foo.sh`
- `test-foo.sh`

Reason: the directory already says it is a test; the extra prefix adds noise and makes rebases harder.

### Case names

Case ids should describe exactly one behavior:

- Good: `release-kernel-contains-rodata-section`
- Good: `no-dynamic-section`
- Good: `rust-references-bss-end`
- Bad: `wildcards`
- Bad: `dynamic`
- Bad: `layout-symbols`

If a case name needs `and`, `/`, or a vague umbrella word, it is usually too broad and should be split.

## "One Thing Per Test"

A listed case should fail for one reason.

Good examples:

- `no-pt-interp-segment`
- `no-interp-section`
- `no-dynamic-section`

Bad example:

- one case that checks PT_INTERP, `.interp`, `.dynamic`, undefined symbols, and strings together

Why this matters:

- failures are easier to read
- rebases are easier because conflict resolution is local
- changed behavior does not force renaming unrelated cases
- old branches can map one old case to several new cases mechanically

The script may still have an internal "run all default checks" path for build gates, but the host-discovered cases should stay granular.

## How To Add A New Script

When adding a new test script:

1. Put it in the correct section directory.
2. Add `set -euo pipefail`.
3. Implement `list_cases`.
4. Implement `describe_case`.
5. Keep each listed case focused on one behavior.
6. Reuse small helper functions when several cases share setup.
7. If the script has a default "run everything" mode, keep that mode separate from the host-discovered case list.

A good pattern is:

```bash
list_cases() { ... }
describe_case() { ... }

run_direct_case() {
  case "${CASE}" in
    one-behavior-case) ... ;;
    another-one-behavior-case) ... ;;
  esac
}
```

## How To Add A New Section

If you want a brand new section directory to show up in the host test output, adding the directory alone is not enough.

You must also update `scripts/test-host.sh` to add another `run_section` call.

Today, section discovery is not dynamic; it is explicit.

## Recent Rename And Split Summary

If your branch was created before the recent cleanup, these are the main file renames.

### Script rename map

| Old path | New path |
| --- | --- |
| `scripts/tests/check-m3.2-sections.sh` | `scripts/tests/kernel-sections.sh` |
| `scripts/stability-tests/check-m3.2-stability.sh` | `scripts/stability-tests/section-stability.sh` |
| `scripts/rejection-tests/check-m3.2-rejections.sh` | `scripts/rejection-tests/section-rejections.sh` |
| `scripts/boot-tests/check-m0.2-freestanding.sh` | `scripts/boot-tests/freestanding-kernel.sh` |
| `scripts/boot-tests/check-m3.3-layout-symbols.sh` | `scripts/boot-tests/layout-symbols.sh` |
| `scripts/boot-tests/test.sh` | `scripts/boot-tests/build-boot-artifacts.sh` |
| `scripts/boot-tests/test-qemu.sh` | `scripts/boot-tests/qemu-boot.sh` |

### Case split map

These old broad cases were split into clearer one-behavior cases.

#### `scripts/stability-tests/check-m3.2-stability.sh`

| Old case | New case(s) |
| --- | --- |
| `wildcards` | `rodata-wildcard-capture`, `data-wildcard-capture`, `bss-wildcard-capture`, `common-wildcard-capture` |
| `rodata-subsection` | `rodata-subsection-marker` |
| `data-subsection` | `data-subsection-marker` |
| `bss-subsection` | `bss-subsection-marker` |
| `common-bss` | `common-bss-marker` |
| `alloc-allowlist` | `alloc-section-allowlist` |

#### `scripts/boot-tests/check-m0.2-freestanding.sh`

| Old case | New case(s) |
| --- | --- |
| `langs` | `rust-marker-symbol-present`, `asm-entry-symbol-present` |
| `interp` | `no-pt-interp-segment` |
| `dynamic` | `no-interp-section`, `no-dynamic-section` |
| `undef` | `no-undefined-symbols` |
| `strings` | `no-libc-strings`, `no-loader-strings` |

#### `scripts/boot-tests/check-m3.3-layout-symbols.sh`

| Old case | New case(s) |
| --- | --- |
| `release-kernel-exports-layout-symbols` | `release-kernel-exports-kernel-start`, `release-kernel-exports-kernel-end`, `release-kernel-exports-bss-start`, `release-kernel-exports-bss-end`, `release-kernel-links-layout-symbols-marker`, `release-symbol-ordering` |
| `test-kernel-exports-layout-symbols` | `test-kernel-exports-kernel-start`, `test-kernel-exports-kernel-end`, `test-kernel-exports-bss-start`, `test-kernel-exports-bss-end`, `test-kernel-links-layout-symbols-marker`, `test-symbol-ordering` |
| `rust-references-layout-symbols` | `rust-declares-layout-symbols`, `rust-references-kernel-start`, `rust-references-kernel-end`, `rust-references-bss-start`, `rust-references-bss-end` |

#### `scripts/tests/check-m3.2-sections.sh`

| Old case | New case(s) |
| --- | --- |
| `linker-script-defines-standard-sections` | `linker-script-defines-rodata-section`, `linker-script-defines-data-section`, `linker-script-defines-bss-section` |
| `release-kernel-contains-standard-sections` | `release-kernel-contains-text-section`, `release-kernel-contains-rodata-section`, `release-kernel-contains-data-section`, `release-kernel-contains-bss-section` |

#### Boot artifact scripts

| Old case | New case(s) |
| --- | --- |
| `build-test-iso` | `build-iso` |
| `build-test-img-artifact` | `build-img-artifact` |
| `grub-boots-test-iso` | `grub-boots-iso` |
| `grub-boots-test-img` | `grub-boots-img` |

## Rebase Tips For Older Branches

If your branch still uses the old framework:

1. Rename script references first.
2. Update any `--description` and `--list` expectations next.
3. Replace old broad case ids with the new split case ids.
4. If your branch adds logic to an old broad case, decide whether that logic belongs in one of the new split cases or in a new case.
5. Re-run `bash <script> --list` to verify the final case surface.

For quick validation after a rebase:

```bash
bash scripts/tests/kernel-sections.sh --list
bash scripts/stability-tests/section-stability.sh --list
bash scripts/rejection-tests/section-rejections.sh --list
bash scripts/rejection-tests/freestanding-rejections.sh --list
bash scripts/rejection-tests/layout-symbol-rejections.sh --list
bash scripts/boot-tests/freestanding-kernel.sh --list
bash scripts/boot-tests/layout-symbols.sh --list
bash scripts/boot-tests/build-boot-artifacts.sh --list
bash scripts/boot-tests/qemu-boot.sh --list
```

And for syntax:

```bash
bash -n scripts/test-host.sh
bash -n scripts/tests/kernel-sections.sh
bash -n scripts/rejection-tests/freestanding-rejections.sh
bash -n scripts/rejection-tests/layout-symbol-rejections.sh
bash -n scripts/boot-tests/layout-symbols.sh
```
