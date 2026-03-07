#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"

# This decides whether the script should use ANSI colors.
want_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ "${KFS_COLOR:-}" == "1" ]] && return 0
  [[ -t 1 ]]
}

# This starts a terminal color sequence when color output is enabled.
color() {
  local code="$1"
  if want_color; then
    printf '\033[%sm' "${code}"
  fi
}

# This resets the terminal style back to normal.
reset_color() {
  if want_color; then
    printf '\033[0m'
  fi
}

# This prints a horizontal divider for readability.
hr() {
  printf '%s\n' "============================================================"
}

# This prints a colored title banner for a test section.
banner() {
  local title="$1"
  hr
  color "1;34"
  printf '%s\n' "${title}"
  reset_color
  hr
}

# This prints a success line.
ok() {
  color "32"
  printf '%s' "$*"
  reset_color
  printf '\n'
}

# This prints a failure line.
bad() {
  color "31"
  printf '%s' "$*"
  reset_color
  printf '\n'
}

# This prints a normal informational line.
note() {
  printf '%s\n' "$*"
}

banner "KFS TEST SUITE"
note "arch: ${ARCH}"

color "1;34"; note "[1/2] toolchain"; reset_color
if bash scripts/dev-env.sh check; then
  printf '%s ' "toolchain:"
  ok "OK"
else
  printf '%s ' "toolchain:"
  bad "FAIL"
  exit 1
fi

note ""
color "1;34"; note "[2/2] qemu exit gate"; reset_color
note "assert: qemu exits via isa-debug-exit on port 0xf4"
note "assert: PASS when rc is ${TEST_PASS_RC:-33}"
note "assert: FAIL when rc is ${TEST_FAIL_RC:-35} or timeout"

if bash scripts/test-qemu.sh "${ARCH}"; then
  ok "RESULT PASS"
  exit 0
fi

bad "RESULT FAIL"
exit 1
