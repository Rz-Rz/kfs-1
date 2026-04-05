# Technology Stack

**Analysis Date:** 2026-04-05

## Languages

**Primary:**
- Rust `no_std` - shared kernel logic in `src/main.rs`, `src/lib.rs`, and `src/kernel/**`

**Secondary:**
- NASM assembly - x86 boot/runtime entry points in `src/arch/i386/*.asm`
- Bash - build and verification harnesses in `scripts/**/*.sh`
- Python 3.10+ - optional Textual test UI and metrics tooling in `scripts/*.py`

## Runtime

**Environment:**
- Freestanding 32-bit x86 kernel image booted by GRUB under `qemu-system-i386`
- Containerized Linux toolchain via `scripts/container.sh` and the repo `Dockerfile`

**Package Manager:**
- No Cargo workspace is used for kernel builds
- Python dependencies are tracked in `requirements.txt`

## Frameworks

**Core:**
- No OS framework; the kernel is a freestanding Rust + ASM image
- GNU binutils linker flow driven by `Makefile`

**Testing:**
- Rust built-in `#[test]` host tests under `tests/*.rs`
- Shell-based architecture, rejection, stability, and boot suites under `scripts/*-tests/`

**Build/Dev:**
- `rustc` emits the Rust kernel object directly from `src/main.rs`
- `nasm` builds boot/runtime objects for `src/arch/i386/*.asm`
- `ld`, `objcopy`, `objdump`, and `readelf` are used for final image creation and artifact proofs

## Key Dependencies

**Critical:**
- `rustc` - Rust object generation for the freestanding kernel
- `nasm` - Multiboot header, entry handoff, and runtime helper assembly
- `ld` - Links the final ELF32 kernel with `src/arch/i386/linker.ld`
- `grub-mkrescue` - Produces bootable ISO images
- `qemu-system-i386` - Runs boot and runtime verification

**Infrastructure:**
- `ripgrep` - fast text assertions in shell tests
- `textual` - optional terminal UI for test orchestration

## Configuration

**Environment:**
- Build/test knobs live mostly in `Makefile`
- Container/runtime overrides use env vars such as `KFS_CONTAINER_ENGINE`, `KFS_USE_KVM`, `KFS_TEST_UI`, and `KFS_SCREEN_GEOMETRY_PRESET`

**Build:**
- `Makefile` is the primary build contract
- `Dockerfile` defines the canonical toolchain image
- `pyproject.toml` and `requirements.txt` configure Python tooling

## Platform Requirements

**Development:**
- Linux-compatible container runtime (`docker` or `podman`)
- QEMU and GRUB available inside the container image

**Production:**
- Boot target is a GRUB-loaded 32-bit x86 kernel image, not a hosted userland program
- Current Rust codegen baseline is `i586-unknown-linux-gnu` while the final linked artifact remains ELF32 `Intel 80386`

---
*Stack analysis: 2026-04-05*
*Update after major toolchain or target changes*
