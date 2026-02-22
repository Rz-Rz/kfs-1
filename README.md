# kfs-1

Workflow: build and run using the container toolchain so it runs in both Fedora and Ubuntu.
and CI on Ubuntu headless Docker behave the same.

## Quickstart

One command:
- `make test`

What it does:
- Builds the dev image if needed
- Checks required tools inside the container
- Builds the ISO
- Runs a headless QEMU test that exits with PASS or FAIL

## When to use each command

- `make test`
  - Use when: daily check that build and boot still work and the test exits with PASS or FAIL
- `make dev`
  - Use when: you want an interactive shell inside the toolchain container
- `make iso-in-container`
  - Use when: you only want to rebuild the ISO
- `make run-in-container`
  - Use when: you want to boot the ISO via QEMU with a graphical window; requires display support inside the container

Optional: if your host has KVM and you want acceleration:
- `KFS_USE_KVM=1 make test`

## Notes
- WSL and CI typically do not have `/dev/kvm`, so the default is to run without KVM. It is slower but consistent.
- Fedora + Podman uses an SELinux-friendly mount label automatically.

## Useful env vars
- `KFS_CONTAINER_ENGINE=docker|podman` forces the container engine
- `KFS_USE_KVM=1` enables KVM if `/dev/kvm` exists
- `KFS_QEMU_SMOKE_TIMEOUT_SECS=5` sets the smoke duration in seconds

## About `arch`
You usually don’t need to care: the default `arch` is auto-detected.
- Today it resolves to `x86_64` because that’s where sources exist in this repo.
- Once `src/arch/i386/` is implemented, it will switch to `i386` automatically.
