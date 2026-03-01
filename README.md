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

It does **not** yet prove:
- ASM boot sets a stack and transfers control to a chosen-language `kmain` (M2/M4)
- Screen interface and displaying `42` (M6)

`make test` also includes an ELF artifact inspection gate for M0.2 (“freestanding / no host libs”).
See `docs/m0_2_freestanding_proofs.md`.

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
