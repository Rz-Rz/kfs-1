# External Integrations

**Analysis Date:** 2026-04-05

## APIs & External Services

This repo does not call network APIs or hosted third-party services at kernel runtime.

**Boot Tooling:**
- GRUB - boots the kernel ISO/image generated from `src/arch/i386/grub.cfg`
  - Integration method: bootloader configuration and ISO assembly
  - Runtime boundary: external to the kernel image itself

**Emulation:**
- QEMU - executes boot/runtime verification from scripts such as `scripts/boot-tests/qemu-boot.sh`
  - Integration method: command-line invocation from shell scripts
  - Runtime boundary: external harness, not linked into the kernel

## Data Storage

**Databases:**
- None

**File Storage:**
- Build artifacts only: `build/kernel-*.bin`, `build/os-*.iso`, `build/os-*.img`

**Caching:**
- None

## Authentication & Identity

**Auth Provider:**
- None

## Monitoring & Observability

**Error Tracking:**
- None

**Analytics:**
- None

**Logs:**
- Serial and marker-based boot diagnostics emitted by kernel/runtime code and consumed by shell harnesses
- Test logs and optional debug outputs are written under temporary files or `KFS_TEST_DEBUG_DIR`

## CI/CD & Deployment

**Hosting:**
- No deployment platform; the output is a local bootable kernel image

**CI Pipeline:**
- No repo-local CI workflow files are present in the analyzed tree
- The main repeatable gate is `make test`

## Environment Configuration

**Development:**
- Containerized toolchain via `scripts/container.sh`
- Python UI tooling via `requirements.txt`
- Make/env flags select container engine, KVM usage, UI mode, and test presets

**Staging:**
- None

**Production:**
- None in the hosted-service sense; the artifact is an ELF32 kernel booted by GRUB

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

## External Binaries That Matter

These are the real "outside the repo" dependencies that matter for development and verification:
- `rustc`
- `nasm`
- `ld`
- `objcopy`
- `objdump`
- `readelf`
- `grub-mkrescue`
- `qemu-system-i386`

The subject-critical rule is that the final kernel must not link against host runtime libraries. These tools build and inspect the kernel but are not linked into it.

---
*Integrations analysis: 2026-04-05*
*Update when external build/runtime dependencies change*
