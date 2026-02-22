#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-x86_64}"
TIMEOUT_SECS="${KFS_QEMU_SMOKE_TIMEOUT_SECS:-5}"
USE_KVM="${KFS_USE_KVM:-0}"

die() {
  echo "error: $*" >&2
  exit 1
}

qemu_bin() {
  case "${ARCH}" in
    i386) echo "qemu-system-i386" ;;
    x86_64) echo "qemu-system-x86_64" ;;
    *) die "unsupported arch for smoke: ${ARCH} (expected i386 or x86_64)" ;;
  esac
}

iso_path() {
  echo "build/os-${ARCH}.iso"
}

main() {
  local qemu
  qemu="$(qemu_bin)"

  local iso
  iso="$(iso_path)"
  [[ -f "${iso}" ]] || die "missing ISO: ${iso} (build it first)"

  local accel=()
  if [[ "${USE_KVM}" == "1" && -e /dev/kvm ]]; then
    accel=(-enable-kvm)
  fi

  set +e
  timeout "${TIMEOUT_SECS}" \
    "${qemu}" \
      -cdrom "${iso}" \
      -nographic \
      -no-reboot \
      -no-shutdown \
      "${accel[@]}" \
      >/dev/null 2>&1
  local rc=$?
  set -e

  if [[ "${rc}" -eq 124 ]]; then
    echo "qemu-smoke: PASS (ran for ${TIMEOUT_SECS}s)"
    exit 0
  fi

  die "qemu-smoke: FAIL (qemu exited early, rc=${rc})"
}

main

