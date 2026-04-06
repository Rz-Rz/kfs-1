# kfs-1

Workflow: build and test using the container toolchain so Fedora and Ubuntu WSL run the same commands.
Release artifact reproducibility is tracked separately from runtime correctness: the build now derives `SOURCE_DATE_EPOCH` from Git, remaps Rust build paths, and checks that release artifacts match across clean rebuilds.

## Quickstart

One command:
- `make test`

Optional:
- `make test-ui-bootstrap` installs the host-side Python TUI dependencies into `.venv-test-ui`

What it does:
- Rebuilds the dev image
- Checks required tools inside the container
- Checks the tracked release ISO/disk-image artifacts (type + size)
- Builds the test ISO/disk-image artifacts
- Runs headless QEMU boot/runtime checks
- Asserts the first VGA text-memory bytes for `42` without any GUI and verifies the buffer is stable across repeated QEMU monitor snapshots
- Verifies release artifacts are byte-identical across clean rebuilds and across copied workdirs

## What the test proves

`make test` is a deterministic, headless PASS/FAIL gate.
It currently proves the following **subject** requirements:
- “Install GRUB on a virtual image” (boots ISO/IMG via GRUB in QEMU)
- “Your work must not exceed 10 MB” (checks tracked release ISO/IMG sizes)
- “must not be linked to any existing library on that host” / freestanding (ELF inspection gate; M0.2)
- “use GRUB to init and call main function of the kernel” / chosen-language kernel entry (release symbol + callsite proofs, plus runtime serial markers for `kmain`; M2/M4)
- Rust early init validates basic runtime assumptions before the normal flow (BSS-zero and layout-range runtime proofs; M4.2)
- The mandatory screen path prints `42` and VGA text memory begins with the expected `42` bytes (M6 / I2)

It does **not** yet directly prove:
- Bonus cursor/scroll behavior is complete (B1)
- The screen interface is a full general-purpose console API beyond the current minimal writer path

`make test` also includes an ELF artifact inspection gate for M0.2 (“freestanding / no host libs”).
See `docs/m0_2_freestanding_proofs.md`.
It also includes runtime serial-marker proofs for M4 under QEMU.

## When to use each command

- `make test`
  - Use when: daily red or green gate
- `make test-vga`
  - Use when: run only the headless VGA-memory assertion path
- `make test-ui`
  - Use when: force the retro Textual TUI on an interactive host terminal
- `make test-plain`
  - Use when: force the plain shell output even on an interactive terminal
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
- `KFS_VGA_BOOT_WAIT_SECS=1` sets how long the VGA-memory harness waits before reading `0xB8000`
- `KFS_TEST_UI=0|1|auto` forces plain tests, forces the TUI, or auto-selects based on TTY/CI (default: `auto`)
