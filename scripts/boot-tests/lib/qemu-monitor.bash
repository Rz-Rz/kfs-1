#!/usr/bin/env bash

qemu_monitor_die() {
  echo "error: $*" >&2
  exit 2
}

qemu_monitor_addr_pattern() {
  printf '%x:.*0x[0-9a-f]{2}' "$1"
}

qemu_monitor_sendkey() {
  printf 'sendkey %s\n' "$1"
}

qemu_monitor_dump_bytes() {
  local count="$1"
  local addr="$2"
  printf 'xp /%dbx 0x%x\n' "${count}" "${addr}"
}

qemu_monitor_quit() {
  printf 'quit\n'
}

qemu_monitor_capture_release_iso() {
  local arch="$1"
  local iso="$2"
  local log="$3"
  local timeout_secs="$4"
  local script_fn="$5"
  local boot_wait_secs="$6"

  [[ "${arch}" == "i386" ]] || qemu_monitor_die "unsupported arch: ${arch}"
  [[ -r "${iso}" ]] || qemu_monitor_die "missing ISO: ${iso}"
  declare -F "${script_fn}" >/dev/null 2>&1 || qemu_monitor_die "unknown monitor script function: ${script_fn}"

  set +e
  {
    sleep "${boot_wait_secs}"
    "${script_fn}"
  } | timeout --foreground "${timeout_secs}" \
    qemu-system-i386 \
    -cdrom "${iso}" \
    -boot d \
    -monitor stdio \
    -serial none \
    -display none \
    -no-reboot \
    -no-shutdown \
    >"${log}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    echo "FAIL: qemu monitor capture failed (rc=${rc})" >&2
    cat "${log}" >&2
    exit 1
  fi
}

qemu_monitor_dump_lines() {
  local log="$1"
  local addr="$2"

  grep -Ei "$(qemu_monitor_addr_pattern "${addr}")" "${log}" || true
}

qemu_monitor_dump_line() {
  local log="$1"
  local addr="$2"
  local ordinal="$3"
  local line

  line="$(qemu_monitor_dump_lines "${log}" "${addr}" | sed -n "${ordinal}p")"
  [[ -n "${line}" ]] || {
    echo "FAIL: missing VGA dump ${ordinal} for 0x$(printf '%x' "${addr}")" >&2
    cat "${log}" >&2
    exit 1
  }

  printf '%s\n' "${line}"
}

qemu_monitor_assert_dump_matches() {
  local log="$1"
  local addr="$2"
  local ordinal="$3"
  local pattern="$4"
  local line

  line="$(qemu_monitor_dump_line "${log}" "${addr}" "${ordinal}")"
  if ! printf '%s\n' "${line}" | grep -Eq "${pattern}"; then
    echo "FAIL: unexpected VGA dump ${ordinal} for 0x$(printf '%x' "${addr}")" >&2
    printf '%s\n' "${line}" >&2
    cat "${log}" >&2
    exit 1
  fi
}
