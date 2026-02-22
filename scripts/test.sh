#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"

want_color() {
  [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]
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

note "TEST SUITE"

bash scripts/dev-env.sh check

if bash scripts/test-qemu.sh "${ARCH}"; then
  ok "RESULT PASS"
  exit 0
fi

bad "RESULT FAIL"
exit 1

