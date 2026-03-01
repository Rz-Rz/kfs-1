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

info() {
  color "2"
  printf '%s' "$*"
  reset_color
}

pass() {
  color "32"
  printf '%s' "PASS"
  reset_color
}

fail() {
  color "31"
  printf '%s' "FAIL"
  reset_color
}

indent() {
  sed 's/^/  /'
}

run_item() {
  local idx="$1"
  local total="$2"
  local title="$3"
  shift 3

  color "1;34"
  printf '[%s/%s] %s ' "${idx}" "${total}" "${title}"
  reset_color

  local log
  log="$(mktemp -t kfs-test.XXXXXX)"
  set +e
  "$@" >"${log}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    pass
    printf '\n'
    if [[ "${VERBOSE}" == "1" ]]; then
      cat "${log}" | indent
    fi
    rm -f "${log}"
    return 0
  fi

  fail
  printf '\n'
  cat "${log}" | indent
  rm -f "${log}"
  return "${rc}"
}

run_item_inline() {
  local idx="$1"
  local total="$2"
  local title="$3"
  shift 3

  color "1;34"
  printf '[%s/%s] %s ' "${idx}" "${total}" "${title}"
  reset_color

  local log rc
  log="$(mktemp -t kfs-test.XXXXXX)"
  set +e
  "$@" >"${log}" 2>&1
  rc="$?"
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    pass
    printf '\n'
    if [[ "${VERBOSE}" == "1" ]]; then
      cat "${log}" | indent
    fi
    rm -f "${log}"
    return 0
  fi

  fail
  printf '\n'
  cat "${log}" | indent
  rm -f "${log}"
  return "${rc}"
}

[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

export KFS_CONTAINER_TTY=0
is_tty && export KFS_CONTAINER_TTY=1

banner "KFS TESTS"
info "arch: ${ARCH}"
printf '\n'

color "1;34"; printf '%s\n' "SETUP"; reset_color
run_item 1 2 "Rebuild the container toolchain image" \
  env KFS_FORCE_IMAGE_BUILD=1 bash scripts/container.sh build-image

run_item 2 2 "Verify tools exist" \
  bash scripts/container.sh env-check

printf '\n'
color "1;34"; printf '%s\n' "TESTS"; reset_color
run_item 1 14 "release ISO is bootable" \
  bash scripts/container.sh run -- \
    bash -lc "make -B iso arch='${ARCH}' >/dev/null && test -f build/os-${ARCH}.iso && test \$(wc -c < build/os-${ARCH}.iso) -le 10485760 && file build/os-${ARCH}.iso | grep -q 'ISO 9660'"

run_item 2 14 "kmain exists + is called (M4.1)" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m4.1-kmain.sh '${ARCH}'"

run_item 3 14 "release IMG is bootable" \
  bash scripts/container.sh run -- \
    bash -lc "make -B img arch='${ARCH}' >/dev/null && test -f build/os-${ARCH}.img && test \$(wc -c < build/os-${ARCH}.img) -le 10485760 && file build/os-${ARCH}.img | grep -q 'ISO 9660' && cmp -s build/os-${ARCH}.iso build/os-${ARCH}.img"

run_item 4 14 "Build test ISO" \
  bash scripts/container.sh run -- \
    bash -lc "make -B iso-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL}' >/dev/null"

run_item 5 14 "standard sections exist (.text/.rodata/.data/.bss)" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.2-sections.sh '${ARCH}'"

run_item 6 14 "layout symbols exported + referenced (M3.3)" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m3.3-layout-symbols.sh '${ARCH}'"

run_item 7 14 "kernel includes ASM+Rust (symbol gate)" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' langs"

run_item 8 14 "no host libs (ELF checks): no PT_INTERP" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' interp"

run_item 9 14 "no host libs (ELF checks): no .interp/.dynamic" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' dynamic"

run_item 10 14 "no host libs (ELF checks): no undefined symbols" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' undef"

run_item 11 14 "no host libs (ELF checks): no libc/loader strings" \
  bash scripts/container.sh run -- \
    bash -lc "bash scripts/check-m0.2-freestanding.sh '${ARCH}' strings"

run_item_inline 12 14 "GRUB boots test ISO" \
  bash scripts/container.sh run -- env \
    TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS}" \
    TEST_PASS_RC="${TEST_PASS_RC}" \
    TEST_FAIL_RC="${TEST_FAIL_RC}" \
    KFS_TEST_FORCE_FAIL="${KFS_TEST_FORCE_FAIL}" \
    bash scripts/test-qemu.sh "${ARCH}"

run_item 13 14 "Build test IMG artifact" \
  bash scripts/container.sh run -- \
    bash -lc "make -B img-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL}' >/dev/null"

run_item_inline 14 14 "GRUB boots test IMG" \
  bash scripts/container.sh run -- env \
    TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS}" \
    TEST_PASS_RC="${TEST_PASS_RC}" \
    TEST_FAIL_RC="${TEST_FAIL_RC}" \
    KFS_TEST_FORCE_FAIL="${KFS_TEST_FORCE_FAIL}" \
    bash scripts/test-qemu.sh "${ARCH}" drive

printf '\n'
pass
printf ' %s\n' "SUMMARY PASS"
