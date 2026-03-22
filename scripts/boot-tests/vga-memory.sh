#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-all}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
BOOT_WAIT_SECS="${KFS_VGA_BOOT_WAIT_SECS:-1}"
ISO="build/os-${ARCH}.iso"
LOG="build/vga-memory-${ARCH}-${CASE}.log"

list_cases() {
  cat <<'EOF'
vga-buffer-starts-with-42
vga-buffer-uses-default-attribute
vga-buffer-stable-across-snapshots
EOF
}

describe_case() {
  case "$1" in
    vga-buffer-starts-with-42) printf '%s\n' "VGA memory starts with the bytes for 42" ;;
    vga-buffer-uses-default-attribute) printf '%s\n' "VGA memory uses the default attribute for the printed 42" ;;
    vga-buffer-stable-across-snapshots) printf '%s\n' "VGA memory stays stable across repeated monitor snapshots" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

run_qemu_capture() {
  [[ -r "${ISO}" ]] || die "missing ISO: ${ISO} (build it with make iso arch=${ARCH})"

  set +e
  {
    sleep "${BOOT_WAIT_SECS}"
    printf 'xp /8bx 0xb8000\n'
    sleep 1
    printf 'xp /8bx 0xb8000\n'
    sleep 1
    printf 'quit\n'
  } | timeout --foreground "${TIMEOUT_SECS}" \
    qemu-system-i386 \
    -cdrom "${ISO}" \
    -boot d \
    -monitor stdio \
    -serial none \
    -display none \
    -no-reboot \
    -no-shutdown \
    >"${LOG}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    echo "FAIL ${CASE}: qemu monitor capture failed (rc=${rc})" >&2
    cat "${LOG}" >&2
    exit 1
  fi
}

capture_lines() {
  local line

  line="$(grep -Ei 'b8000:.*0x[0-9a-f]{2}' "${LOG}" | tail -n 2 || true)"
  [[ -n "${line}" ]] || {
    echo "FAIL ${CASE}: missing VGA memory dump for 0xb8000" >&2
    cat "${LOG}" >&2
    exit 1
  }

  printf '%s\n' "${line}"
}

assert_first_snapshot_contains_pattern() {
  local pattern="$1"
  local line

  line="$(capture_lines | head -n 1)"
  if ! printf '%s\n' "${line}" | grep -Eq "${pattern}"; then
    echo "FAIL ${CASE}: unexpected VGA memory bytes" >&2
    printf '%s\n' "${line}" >&2
    cat "${LOG}" >&2
    exit 1
  fi
}

assert_snapshots_are_stable() {
  local first_snapshot
  local second_snapshot
  local -a snapshots

  mapfile -t snapshots < <(capture_lines)

  if [[ "${#snapshots[@]}" -lt 2 ]]; then
    echo "FAIL ${CASE}: expected two VGA memory snapshots" >&2
    cat "${LOG}" >&2
    exit 1
  fi

  first_snapshot="${snapshots[0]}"
  second_snapshot="${snapshots[1]}"

  if [[ "${first_snapshot}" != "${second_snapshot}" ]]; then
    echo "FAIL ${CASE}: VGA memory changed between monitor snapshots" >&2
    printf '%s\n' "${first_snapshot}" >&2
    printf '%s\n' "${second_snapshot}" >&2
    cat "${LOG}" >&2
    exit 1
  fi
}

run_case() {
  case "${CASE}" in
    vga-buffer-starts-with-42)
      assert_first_snapshot_contains_pattern '0x34[[:space:]]+0x02[[:space:]]+0x32[[:space:]]+0x02'
      ;;
    vga-buffer-uses-default-attribute)
      assert_first_snapshot_contains_pattern '0x34[[:space:]]+0x02[[:space:]]+0x32[[:space:]]+0x02'
      ;;
    vga-buffer-stable-across-snapshots)
      assert_first_snapshot_contains_pattern '0x34[[:space:]]+0x02[[:space:]]+0x32[[:space:]]+0x02'
      assert_snapshots_are_stable
      ;;
    *)
      die "unknown case: ${CASE}"
      ;;
  esac
}

run_all_cases() {
  local case_id

  run_qemu_capture
  while IFS= read -r case_id; do
    CASE="${case_id}"
    run_case
  done < <(list_cases)
}

run_direct_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  if [[ "${CASE}" == "all" ]]; then
    run_all_cases
    return 0
  fi

  run_qemu_capture
  run_case
}

run_host_case() {
  bash scripts/with-build-lock.sh \
    bash scripts/container.sh run -- \
    bash -lc "make clean >/dev/null 2>&1 || true; make -B iso arch='${ARCH}' >/dev/null && KFS_HOST_TEST_DIRECT=1 TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' KFS_VGA_BOOT_WAIT_SECS='${BOOT_WAIT_SECS}' bash scripts/boot-tests/vga-memory.sh '${ARCH}' '${CASE}'"
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

  if [[ "${CASE}" != "all" ]]; then
    describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  fi

  if [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
    run_host_case
    return 0
  fi

  run_direct_case
}

main "$@"
