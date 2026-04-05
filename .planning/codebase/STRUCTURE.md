# Codebase Structure

**Analysis Date:** 2026-04-05

## Directory Layout

```text
kfs-1/
├── docs/            # Subject, architecture, and feature/proof documents
├── metrics/         # Generated repo metrics artifacts
├── scripts/         # Build, test, lint, and tooling entrypoints
├── src/             # Kernel source: Rust, freestanding support, and x86 asm
├── tests/           # Host-linked Rust unit/integration-style tests
├── .planning/       # GSD planning workspace for roadmap execution
├── Dockerfile       # Canonical toolchain container image
├── Makefile         # Primary build/test contract
├── README.md        # User-facing build/test guide
└── AGENTS.md        # Repo-local architecture and test discipline rules
```

## Directory Purposes

**`src/`:**
- Purpose: production kernel source
- Contains: Rust crate roots, freestanding-only modules, and `src/arch/i386` assembly/linker assets
- Key files: `src/main.rs`, `src/lib.rs`, `src/kernel/mod.rs`, `src/arch/i386/linker.ld`
- Subdirectories: `arch/`, `freestanding/`, `kernel/`

**`scripts/`:**
- Purpose: operational contract for building and proving repo behavior
- Contains: shell harnesses, Python TUI/metrics tools, container wrapper
- Key files: `scripts/test-host.sh`, `scripts/container.sh`, `scripts/stability-tests/freestanding-simd.sh`
- Subdirectories: `architecture-tests/`, `boot-tests/`, `rejection-tests/`, `stability-tests/`, `tests/`

**`tests/`:**
- Purpose: host-linked Rust tests against the `kfs` library root
- Contains: `host_*.rs` test files
- Key files: `tests/host_memory.rs`, `tests/host_string.rs`, `tests/host_vga_writer.rs`
- Subdirectories: none in the current tree

**`docs/`:**
- Purpose: current-state architecture, proof, and feature planning documents
- Contains: subject PDF, architecture notes, feature backlog/spec docs
- Key files: `docs/subject.pdf`, `docs/kernel_architecture.md`, `docs/m0_2_freestanding_proofs.md`

## Key File Locations

**Entry Points:**
- `src/main.rs`: freestanding Rust crate root
- `src/lib.rs`: host-linked library root
- `src/arch/i386/boot.asm`: assembly entry `start`
- `Makefile`: build/test command entrypoint

**Configuration:**
- `Makefile`: target, build flags, test entrypoints
- `Dockerfile`: containerized toolchain
- `pyproject.toml`: Python formatting/lint settings
- `.planning/config.json`: GSD workflow preferences

**Core Logic:**
- `src/kernel/core/`: entry and early init
- `src/kernel/services/`: console and diagnostics orchestration
- `src/kernel/drivers/`: serial, VGA text, keyboard
- `src/kernel/machine/`: typed low-level primitives
- `src/kernel/klib/`: memory and string helper families

**Testing:**
- `tests/`: host Rust tests
- `scripts/*-tests/`: shell suites by proof category

**Documentation:**
- `docs/`: live repo docs
- `AGENTS.md`: non-negotiable repo discipline

## Naming Conventions

**Files:**
- Rust modules use `mod.rs` plus snake_case leaf files such as `entry.rs`, `init.rs`, `writer.rs`
- Host tests use `host_*.rs`
- Shell scripts use descriptive kebab/snake names ending in `.sh`

**Directories:**
- Kernel layer directories mirror ownership domains: `core`, `drivers`, `klib`, `machine`, `services`, `types`
- Test suites are grouped by intent, not by language

**Special Patterns:**
- `src/kernel/mod.rs` is the canonical shared module root
- `src/freestanding/` is the only freestanding-only Rust subtree

## Where to Add New Code

**New SIMD/MMX policy or runtime setup:**
- Early boot/runtime policy: `src/kernel/core/` and `src/arch/i386/`
- Low-level SIMD register/control helpers: `src/kernel/machine/` or carefully justified `src/arch/i386/`
- Freestanding-only panic/marker support: `src/freestanding/`

**New accelerated memory/string routines:**
- Public helper surface: `src/kernel/klib/memory/mod.rs` or `src/kernel/klib/string/mod.rs`
- Private implementation leafs: `src/kernel/klib/*/imp.rs`
- Host semantic tests: `tests/host_memory.rs`, `tests/host_string.rs`

**New proof or regression tests:**
- Artifact/boot/stability checks: `scripts/stability-tests/` and `scripts/boot-tests/`
- Architecture/rejection guards: `scripts/architecture-tests/`, `scripts/rejection-tests/`
- Live docs: `docs/`

## Special Directories

**`build/`:**
- Purpose: generated kernel and test artifacts
- Source: `Makefile` and test harnesses
- Committed: No

**`.planning/`:**
- Purpose: GSD planning state, roadmap, and codebase map
- Source: planning workflow artifacts
- Committed: Yes for this branch because `commit_docs` is enabled

---
*Structure analysis: 2026-04-05*
*Update when directory structure changes*
