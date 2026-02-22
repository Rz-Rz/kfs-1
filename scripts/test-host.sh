#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
VERBOSE="${KFS_VERBOSE:-0}"

TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
TEST_PASS_RC="${TEST_PASS_RC:-33}"
TEST_FAIL_RC="${TEST_FAIL_RC:-35}"
KFS_TEST_FORCE_FAIL="${KFS_TEST_FORCE_FAIL:-0}"

die() {
  echo "error: $*" >&2
  exit 2
}

is_tty() {
  [[ -t 1 ]]
}

want_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ "${KFS_COLOR:-}" == "1" ]] && return 0
  is_tty
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

banner() {
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
}

bad() {
  color "31"
  printf '%s' "$*"
  reset_color
}

info() {
  color "2"
  printf '%s' "$*"
  reset_color
}

indent() {
  sed 's/^/  /'
}

run_step() {
  local idx="$1"
  local total="$2"
  local name="$3"
  shift 3

  color "1;34"
  printf '[%s/%s] %-18s ' "${idx}" "${total}" "${name}"
  reset_color

  local log
  log="$(mktemp -t kfs-test.XXXXXX)"
  set +e
  "$@" >"${log}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    ok "OK"
    printf '\n'
    if [[ "${VERBOSE}" == "1" ]]; then
      cat "${log}" | indent
    fi
    rm -f "${log}"
    return 0
  fi

  bad "FAIL"
  printf '\n'
  cat "${log}" | indent
  rm -f "${log}"
  return "${rc}"
}

[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

if is_tty; then
  export KFS_CONTAINER_TTY=1
else
  export KFS_CONTAINER_TTY=0
fi

banner "KFS TEST"
info "arch: ${ARCH}"
printf '\n'

run_step 1 3 "image build" \
  env KFS_FORCE_IMAGE_BUILD=1 bash scripts/container.sh build-image

run_step 2 3 "toolchain" \
  bash scripts/container.sh env-check

color "1;34"
printf '[%s/%s] %-18s ' "3" "3" "qemu gate"
reset_color

info "checks: qemu exits on port 0xf4"
printf '\n'

log="$(mktemp -t kfs-test.XXXXXX)"
set +e
bash scripts/container.sh run -- env \
  TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS}" \
  TEST_PASS_RC="${TEST_PASS_RC}" \
  TEST_FAIL_RC="${TEST_FAIL_RC}" \
  KFS_TEST_FORCE_FAIL="${KFS_TEST_FORCE_FAIL}" \
  bash scripts/test-qemu.sh "${ARCH}" >"${log}" 2>&1
rc="$?"
set -e

if [[ "${rc}" -eq 0 ]]; then
  ok "result: PASS"
  printf '\n'
  if [[ "${VERBOSE}" == "1" ]]; then
    cat "${log}" | indent
  fi
  rm -f "${log}"
  exit 0
fi

bad "result: FAIL"
printf '\n'
cat "${log}" | indent
rm -f "${log}"
exit 1

