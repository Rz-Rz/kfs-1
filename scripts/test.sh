#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"

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
  printf '%s\n' "============================================================"
}

section() {
  local title="$1"
  hr
  color "1;34"
  printf '%s\n' "${title}"
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

section "KFS TEST SUITE"
note "arch: ${ARCH}"
note ""

note "STEP 1  toolchain"
bash scripts/dev-env.sh check
note ""

note "STEP 2  boot and deterministic exit gate"
note "This is a single gate test"
note "It checks the kernel boots far enough to signal PASS or FAIL and QEMU exits"
if bash scripts/test-qemu.sh "${ARCH}"; then
  ok "RESULT  PASS"
  exit 0
fi

bad "RESULT  FAIL"
exit 1
