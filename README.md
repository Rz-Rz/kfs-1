# kfs-1

Workflow: build and test using the container toolchain so Fedora and Ubuntu WSL run the same commands.

## Quickstart

One command:
- `make test`

What it does:
- Rebuilds the dev image
- Checks required tools inside the container
- Builds the test ISO
- Runs a headless QEMU test that exits with PASS or FAIL

## What the test proves

The QEMU test is a deterministic exit gate.
It proves the build works and the kernel boots far enough to signal PASS or FAIL.
It does not prove the subject features like printing 42 yet.

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
