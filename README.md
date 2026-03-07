# kfs-1

Workflow: build and test using the container toolchain so Fedora and Ubuntu WSL run the same commands.

## Quickstart

One command:
- `make test`

What it does:
- Rebuilds the dev image
- Checks required tools inside the container
- Checks the tracked release ISO/disk-image artifacts (type + size)
- Builds the test ISO/disk-image artifacts
- Runs a headless QEMU test that exits with PASS or FAIL

## What the test proves

`make test` is a deterministic, headless PASS/FAIL gate.
It currently proves the following **subject** requirements:
- “Install GRUB on a virtual image” (boots ISO/IMG via GRUB in QEMU)
- “Your work must not exceed 10 MB” (checks tracked release ISO/IMG sizes)
- “must not be linked to any existing library on that host” / freestanding (ELF inspection gate; M0.2)
- “use GRUB to init and call main function of the kernel” / chosen-language kernel entry (release symbol + callsite proofs, plus runtime serial markers for `kmain`; M2/M4)
- Rust early init validates basic runtime assumptions before the normal flow (BSS-zero and layout-range runtime proofs; M4.2)

It does **not** yet directly prove:
- The screen interface is complete as an API (M6.1/M6.2)
- The visible VGA output itself is asserted headlessly; `42` is still proved by source inspection rather than by reading VGA memory (M6.3)

`make test` also includes an ELF artifact inspection gate for M0.2 (“freestanding / no host libs”).
See `docs/m0_2_freestanding_proofs.md`.
It also includes runtime serial-marker proofs for M4 under QEMU.

## When to use each command

- `make test`
  - Use when: daily red or green gate
- `make dev`
  - Use when: interactive shell inside the toolchain container
- `make iso-in-container`
  - Use when: rebuild the ISO only
- `make run-in-container`
  - Use when: boot the ISO via QEMU with a graphical window

Optional: if your host has KVM and you want acceleration
- `KFS_USE_KVM=1 make test`

## Notes
- WSL and CI typically do not have `/dev/kvm`, so the default is to run without KVM
- Fedora Podman uses an SELinux friendly mount label automatically

## Useful env vars
- `KFS_CONTAINER_ENGINE=docker|podman` forces the container engine
- `KFS_USE_KVM=1` enables KVM if `/dev/kvm` exists
- `KFS_QEMU_SMOKE_TIMEOUT_SECS=5` sets the smoke duration in seconds
