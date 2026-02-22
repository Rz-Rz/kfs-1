#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
FAIL_RC="${TEST_FAIL_RC:-35}"
ISO="build/os-${ARCH}-test.iso"

die() {
  echo "error: $*" >&2
  exit 2
}

want_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ "${KFS_COLOR:-}" == "1" ]] && return 0
  [[ -t 1 ]]
}

color() {
  local code="$1"
  if want_color; then
    printf '\033[%sm' "${code}"
  fi
}

reset_color() {
  if want_color; then
    printf '\033[0m'
  fi
}

hr() {
  printf '%s\n' "------------------------------------------------------------"
}

title() {
  local t="$1"
  hr
  color "1;34"
  printf '%s\n' "${t}"
  reset_color
  hr
}

ok() {
  color "32"
  printf '%s' "$*"
  reset_color
  printf '\n'
}

bad() {
  color "31"
  printf '%s' "$*"
  reset_color
  printf '\n'
}

note() {
  printf '%s\n' "$*"
}

[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

qemu_kvm_args=()
qemu_accel="tcg"
if [[ -e /dev/kvm ]]; then
  qemu_kvm_args+=(-enable-kvm)
  qemu_accel="kvm"
fi

title "TEST  test-qemu"
note "arch: ${ARCH}"
note "iso: ${ISO}"
note "accel: ${qemu_accel}"
note "timeout: ${TIMEOUT_SECS}s"

make -B iso-test arch="${ARCH}" >/dev/null
note "build: OK"

set +e
timeout --foreground "${TIMEOUT_SECS}" \
  qemu-system-i386 \
  -cdrom "${ISO}" \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -nographic \
  -no-reboot \
  -no-shutdown \
  "${qemu_kvm_args[@]}" \
  </dev/null >/dev/null 2>&1
rc="$?"
set -e

if [[ "${rc}" -eq 124 ]]; then
  bad "FAIL  timeout"
  exit 1
fi
if [[ "${rc}" -eq "${PASS_RC}" ]]; then
  ok "PASS"
  exit 0
fi
if [[ "${rc}" -eq "${FAIL_RC}" ]]; then
  bad "FAIL"
  exit 1
fi

bad "FAIL  rc=${rc}"
exit 1
