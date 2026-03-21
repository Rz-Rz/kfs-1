#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

list_cases() {
  cat <<'EOF'
runtime-path-artifacts-exist
boot-start-hand-off-only-to-kmain
start-not-direct-to-driver-or-helper
entry-calls-core-init-sequence
core-init-calls-services-console
services-console-calls-driver-facade
entry-no-direct-driver-abi-calls
EOF
}

describe_case() {
  case "$1" in
    runtime-path-artifacts-exist) printf '%s\n' "runtime ownership artifacts exist for start -> core -> services -> drivers path" ;;
    boot-start-hand-off-only-to-kmain) printf '%s\n' "boot start handoff enters kmain directly" ;;
    start-not-direct-to-driver-or-helper) printf '%s\n' "boot handoff does not jump directly to driver/helper surfaces" ;;
    entry-calls-core-init-sequence) printf '%s\n' "core entry invokes the core init sequence" ;;
    core-init-calls-services-console) printf '%s\n' "core init delegates console work to services console" ;;
    services-console-calls-driver-facade) printf '%s\n' "services console reaches VGA through driver facade" ;;
    entry-no-direct-driver-abi-calls) printf '%s\n' "core entry does not call or declare VGA driver ABI directly" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

pick_kmain_file() {
  [[ -f "${REPO_ROOT}/src/kernel/core/entry.rs" ]] || return 1
  printf '%s\n' "${REPO_ROOT}/src/kernel/core/entry.rs"
}

assert_runtime_path_artifacts() {
  local missing=()
  local path

  for path in \
    "src/arch/${ARCH}/boot.asm" \
    "src/kernel/core/entry.rs" \
    "src/kernel/core/init.rs" \
    "src/kernel/services/diagnostics.rs" \
    "src/kernel/drivers/serial/mod.rs" \
    "src/kernel/services/console.rs" \
    "src/kernel/drivers/vga_text/mod.rs" \
    "src/kernel/drivers/vga_text/writer.rs"; do
    [[ -f "${REPO_ROOT}/${path}" ]] || missing+=("${path}")
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "FAIL ${CASE}: missing required runtime ownership files"
    printf '%s\n' "${missing[@]}"
    return 1
  fi

  echo "PASS ${CASE}: required runtime ownership files exist"
}

assert_boot_handoff_to_kmain() {
  local boot="${REPO_ROOT}/src/arch/${ARCH}/boot.asm"
  local offending

  [[ -f "${boot}" ]] || {
    echo "FAIL ${CASE}: missing boot asm ${boot}"
    return 1
  }

  if ! rg -n '^\s*call\s+kmain\b' "${boot}" >/dev/null; then
    echo "FAIL ${CASE}: start label does not call kmain"
    return 1
  fi

  offending="$(rg -n '^\s*call\s+(?!kmain\b)[A-Za-z_][A-Za-z0-9_]*' -P "${boot}" || true)"
  if [[ -n "${offending}" ]]; then
    echo "FAIL ${CASE}: boot calls a symbol other than kmain"
    printf '%s\n' "${offending}"
    return 1
  fi

  echo "PASS ${CASE}: boot handoff goes directly to kmain"
}

assert_entry_init_chain() {
  local entry_file="${REPO_ROOT}/src/kernel/core/entry.rs"

  [[ -f "${entry_file}" ]] || {
    echo "FAIL ${CASE}: missing core entry source ${entry_file}"
    return 1
  }

  if ! rg -n '\bfn[[:space:]]+kmain\b' "${entry_file}" >/dev/null; then
    echo "FAIL ${CASE}: core entry file has no kmain export"
    return 1
  fi

  if ! rg -n '\b(run_early_init|init)\s*\(' "${entry_file}" >/dev/null; then
    echo "FAIL ${CASE}: kmain does not reference core init sequencing"
    return 1
  fi

  echo "PASS ${CASE}: kmain references core init sequencing"
}

assert_core_init_calls_services() {
  local init_file="${REPO_ROOT}/src/kernel/core/init.rs"

  [[ -f "${init_file}" ]] || {
    echo "FAIL ${CASE}: missing core init source ${init_file}"
    return 1
  }

  if ! rg -n '\bservices::console\b' "${init_file}" >/dev/null; then
    echo "FAIL ${CASE}: core init does not call services console"
    return 1
  fi

  if rg -n '\bdrivers::vga_text\b' "${init_file}" >/dev/null; then
    echo "FAIL ${CASE}: core init calls driver facade directly"
    return 1
  fi

  echo "PASS ${CASE}: core init delegates to services console"
}

assert_services_console_calls_driver_facade() {
  local console_file="${REPO_ROOT}/src/kernel/services/console.rs"

  [[ -f "${console_file}" ]] || {
    echo "FAIL ${CASE}: missing services console source ${console_file}"
    return 1
  }

  if ! rg -n '\bdrivers::vga_text\b' "${console_file}" >/dev/null; then
    echo "FAIL ${CASE}: services console does not reach VGA driver facade"
    return 1
  fi

  echo "PASS ${CASE}: services console reaches driver facade"
}

assert_entry_no_driver_abi() {
  local kmain_file
  local offenders

  if ! kmain_file="$(pick_kmain_file)"; then
    echo "FAIL ${CASE}: missing core entry source"
    return 1
  fi

  offenders="$(rg -n '\bvga_[A-Za-z_][A-Za-z0-9_]*\b' "${kmain_file}" || true)"
  if [[ -n "${offenders}" ]]; then
    echo "FAIL ${CASE}: kmain entry file contains direct VGA ABI usage"
    printf '%s\n' "${offenders}"
    return 1
  fi

  echo "PASS ${CASE}: kmain entry does not reference VGA ABI directly"
}

assert_boot_does_not_jump_to_driver() {
  local boot="${REPO_ROOT}/src/arch/${ARCH}/boot.asm"
  [[ -f "${boot}" ]] || {
    echo "FAIL ${CASE}: missing boot asm ${boot}"
    return 1
  }

  if rg -n '^\s*call\s+(vga_|kfs_|drivers?)' -P "${boot}" >/dev/null; then
    echo "FAIL ${CASE}: boot asm contains forbidden helper/driver call"
    return 1
  fi

  echo "PASS ${CASE}: boot uses kmain-only handoff"
}

run_case() {
  case "${CASE}" in
    runtime-path-artifacts-exist) assert_runtime_path_artifacts ;;
    boot-start-hand-off-only-to-kmain) assert_boot_handoff_to_kmain ;;
    start-not-direct-to-driver-or-helper) assert_boot_does_not_jump_to_driver ;;
    entry-calls-core-init-sequence) assert_entry_init_chain ;;
    core-init-calls-services-console) assert_core_init_calls_services ;;
    services-console-calls-driver-facade) assert_services_console_calls_driver_facade ;;
    entry-no-direct-driver-abi-calls) assert_entry_no_driver_abi ;;
    *) die "unknown case: ${CASE}" ;;
  esac
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

  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
  describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  run_case
}

main "$@"
