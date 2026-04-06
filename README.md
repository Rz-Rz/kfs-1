# kfs-1

Workflow: build and test using the container toolchain so Fedora and Ubuntu WSL run the same commands.
Release artifact reproducibility is tracked separately from runtime correctness: the build now derives `SOURCE_DATE_EPOCH` from Git, remaps Rust build paths, and checks that release artifacts match across clean rebuilds.
The build container pins the Ubuntu base image digest plus the Rust and host-tool versions used inside the toolchain image.
The `Makefile` is the public source of truth for compilation: host `make` drives Dockerized `nasm`, `rustc`, `ld`, `objcopy`, and `grub-mkrescue` directly.

## Quickstart

One command:
- `make test`

Optional:
- `make test-ui-bootstrap` installs the host-side Python TUI dependencies into `.venv-test-ui`
- `make run-ui` builds `build/os-i386.img` through the normal Dockerized build graph, then launches the manual UI path
- `make test-artifacts` prebuilds the shared release, test, compact-geometry, and negative-runtime artifacts that the suite consumes
- `make reproducible-builds` proves that release kernel/ISO/IMG artifacts are byte-identical across clean rebuilds and copied workdirs

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

- `make all`
  - Use when: rebuild only the kernel binary `build/kernel-i386.bin`
- `make iso`
  - Use when: rebuild the bootable ISO `build/os-i386.iso`
- `make img`
  - Use when: rebuild the bootable IMG `build/os-i386.img`
- `make run`
  - Use when: build the ISO if needed, then boot it in QEMU
- `make run-iso`
  - Use when: boot an already-built ISO without rebuilding
- `make run-ui`
  - Use when: build the IMG if needed, then boot the manual UI path
- `make test-artifacts`
  - Use when: prebuild every shared artifact that the host-side test suite consumes
- `make reproducible-builds`
  - Use when: run only the release-artifact reproducibility proofs
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
  - Use when: compatibility alias for rebuilding the ISO
- `make run-in-container`
  - Use when: compatibility alias for the container-run helper path

## Build Output

Normal builds print labeled steps instead of raw Docker command lines:

- `ASM`: assemble one `.asm` file into one `.o` object with `nasm`
- `RUST`: compile `src/main.rs` into the Rust object with `rustc`
- `LINK`: link the assembly and Rust objects into `build/kernel-i386.bin` with `ld`
- `OBJCOPY`: trim exported globals in the final kernel symbol table
- `ISO`: package the kernel plus `grub.cfg` into `build/os-i386.iso`
- `IMG`: copy the ISO bytes into `build/os-i386.img`
- `RUN-ISO` / `RUN-UI`: boot the selected artifact in QEMU

If you want the full underlying Docker command lines as well, use:

```bash
KFS_VERBOSE=1 make -B all
KFS_VERBOSE=1 make -B img
```

Optional: if your host has KVM and you want acceleration
- `KFS_USE_KVM=1 make test`

## Notes
- WSL and CI typically do not have `/dev/kvm`, so the default is to run without KVM
- Fedora Podman uses an SELinux friendly mount label automatically

## Useful env vars
- `KFS_CONTAINER_ENGINE=docker|podman` forces the container engine
- `KFS_VERBOSE=1` prints the raw Dockerized tool commands in addition to the labeled build steps
- `KFS_USE_KVM=1` enables KVM if `/dev/kvm` exists
- `KFS_QEMU_SMOKE_TIMEOUT_SECS=5` sets the smoke duration in seconds
- `KFS_VGA_BOOT_WAIT_SECS=1` sets how long the VGA-memory harness waits before reading `0xB8000`
- `KFS_TEST_UI=0|1|auto` forces plain tests, forces the TUI, or auto-selects based on TTY/CI (default: `auto`)
