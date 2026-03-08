#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
ISO="build/os-${ARCH}-test.iso"
LOG="build/m5-string-runtime-${CASE}.log"
KMAIN_SOURCE="src/kernel/kmain.rs"

list_cases() {
  cat <<'EOF'
release-kmain-calls-kfs-strlen
runtime-confirms-strlen
release-kmain-calls-kfs-strcmp
runtime-confirms-strcmp
runtime-confirms-string-helpers
runtime-string-markers-are-ordered
EOF
}

describe_case() {
  case "$1" in
    release-kmain-calls-kfs-strlen) printf '%s\n' "release kmain calls kfs_strlen in the string sanity path" ;;
    runtime-confirms-strlen) printf '%s\n' "runtime emits STRLEN_OK" ;;
    release-kmain-calls-kfs-strcmp) printf '%s\n' "release kmain calls kfs_strcmp in the string sanity path" ;;
    runtime-confirms-strcmp) printf '%s\n' "runtime emits STRCMP_OK" ;;
    runtime-confirms-string-helpers) printf '%s\n' "runtime emits STRING_HELPERS_OK" ;;
    runtime-string-markers-are-ordered) printf '%s\n' "runtime emits STRLEN_OK then STRCMP_OK then STRING_HELPERS_OK in order" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

find_pattern() {
  local pattern="$1"
  shift

  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S "$@" >/dev/null
  else
    grep -En "${pattern}" "$@" >/dev/null
  fi
}

assert_pattern() {
  local pattern="$1"
  local label="$2"
  shift 2

  if ! find_pattern "${pattern}" "$@"; then
    echo "FAIL src: missing ${label}"
    return 1
  fi

  echo "PASS src: ${label}"
  return 0
}

run_qemu_capture() {
  [[ -r "${ISO}" ]] || die "missing ISO: ${ISO} (build it with make iso-test arch=${ARCH})"

  set +e
  timeout --foreground "${TIMEOUT_SECS}" \
    qemu-system-i386 \
    -cdrom "${ISO}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -serial stdio \
    -display none \
    -monitor none \
    -no-reboot \
    -no-shutdown \
    </dev/null >"${LOG}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -ne "${PASS_RC}" ]]; then
    echo "FAIL ${CASE}: expected PASS rc=${PASS_RC}, got rc=${rc}" >&2
    cat "${LOG}" >&2
    exit 1
  fi
}

assert_log_contains() {
  local token="$1"
  if ! grep -qFx "${token}" "${LOG}"; then
    echo "FAIL ${CASE}: missing runtime marker ${token}" >&2
    cat "${LOG}" >&2
    exit 1
  fi
}

assert_log_order() {
  local previous_line=0
  local token
  local line

  for token in "$@"; do
    line="$(grep -nFx "${token}" "${LOG}" | head -n 1 | cut -d: -f1)"
    [[ -n "${line}" ]] || {
      echo "FAIL ${CASE}: missing runtime marker ${token}" >&2
      cat "${LOG}" >&2
      exit 1
    }

    if (( line <= previous_line )); then
      echo "FAIL ${CASE}: runtime marker ${token} is out of order" >&2
      cat "${LOG}" >&2
      exit 1
    fi

    previous_line="${line}"
  done
}

run_direct_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  run_qemu_capture

  case "${CASE}" in
    release-kmain-calls-kfs-strlen)
      assert_pattern 'kfs_strlen\(' 'kfs_strlen call in kmain' "${KMAIN_SOURCE}"
      assert_log_contains "STRLEN_OK"
      ;;
    runtime-confirms-strlen)
      assert_log_contains "STRLEN_OK"
      ;;
    release-kmain-calls-kfs-strcmp)
      assert_pattern 'kfs_strcmp\(' 'kfs_strcmp call in kmain' "${KMAIN_SOURCE}"
      assert_log_contains "STRCMP_OK"
      ;;
    runtime-confirms-strcmp)
      assert_log_contains "STRCMP_OK"
      ;;
    runtime-confirms-string-helpers)
      assert_log_contains "STRING_HELPERS_OK"
      ;;
    runtime-string-markers-are-ordered)
      assert_log_order "STRLEN_OK" "STRCMP_OK" "STRING_HELPERS_OK"
      ;;
    *)
      die "usage: $0 <arch> {release-kmain-calls-kfs-strlen|runtime-confirms-strlen|release-kmain-calls-kfs-strcmp|runtime-confirms-strcmp|runtime-confirms-string-helpers|runtime-string-markers-are-ordered}"
      ;;
  esac
}

run_host_case() {
  bash scripts/with-build-lock.sh \
    bash scripts/container.sh run -- \
    bash -lc "make clean >/dev/null 2>&1 || true; make -B iso-test arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' TEST_PASS_RC='${PASS_RC}' bash scripts/boot-tests/string-runtime.sh '${ARCH}' '${CASE}'"
}

main() {
  if [[ "${ARCH}" == "--list" ]]; then
    list_cases
    return 0
  fi

  if [[ "${ARCH}" == "--description" ]]; then
    describe_case "${CASE}"
    return 0
  fi

  if describe_case "${CASE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  run_direct_case
}

main "$@"
