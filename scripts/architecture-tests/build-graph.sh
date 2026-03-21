#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

MAKE_DB=""
RUST_SOURCE_FILES=""
RUST_OBJECT_FILES=""

list_cases() {
  cat <<'EOF'
kernel-rust-root-is-single-entry
makefile-does-not-glob-src-kernel-peers
build-produces-single-kernel-rust-unit
no-kernel-subsystem-rust-objects
EOF
}

describe_case() {
  case "$1" in
    kernel-rust-root-is-single-entry) printf '%s\n' "src/main.rs is the only kernel crate-root source and src/kernel/*.rs files are not compiled directly" ;;
    makefile-does-not-glob-src-kernel-peers) printf '%s\n' "Makefile does not compile src/kernel/*.rs by glob" ;;
    build-produces-single-kernel-rust-unit) printf '%s\n' "kernel build emits one Rust kernel unit (kernel.o or kernel.a)" ;;
    no-kernel-subsystem-rust-objects) printf '%s\n' "kernel subsystem files are not emitted as separate Rust objects" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

extract_make_var() {
  local var_name="$1"

  awk -v var="${var_name}" '
    $1 == var && ($2=="=" || $2==":=" || $2=="?=" || $2=="+=") {
      $1 = "";
      $2 = "";
      sub(/^[[:space:]]+/, "");
      print;
      exit;
    }
  ' <<<"${MAKE_DB}"
}

load_make_database() {
  MAKE_DB="$(make -np -f "${REPO_ROOT}/Makefile" ARCH="${ARCH}" 2>/dev/null || true)"
  if [[ -z "${MAKE_DB}" ]]; then
    echo "FAIL ${CASE}: failed to load Makefile database"
    return 1
  fi
}

load_make_lists() {
  RUST_SOURCE_FILES="$(extract_make_var "rust_source_files")"
  RUST_OBJECT_FILES="$(extract_make_var "rust_object_files")"

  if [[ -z "${RUST_SOURCE_FILES}" ]]; then
    echo "FAIL ${CASE}: rust_source_files is empty"
    return 1
  fi
}

assert_kernel_root_is_single_entry() {
  mapfile -t kernel_sources < <(
    printf '%s\n' "${RUST_SOURCE_FILES}" |
    tr ' ' '\n' |
    rg '^src/(main\.rs|kernel/[^[:space:]]+\.rs)$' || true
  )

  local -a disallowed_sources=()
  local has_kernel_root=0
  local file

  for file in "${kernel_sources[@]}"; do
    [[ -n "${file}" ]] || continue
    if [[ "${file}" == "src/main.rs" ]]; then
      has_kernel_root=1
    else
      disallowed_sources+=("${file}")
    fi
  done

  if (( has_kernel_root == 0 )); then
    echo "FAIL ${CASE}: src/main.rs is missing from rust_source_files"
    return 1
  fi

  if (( ${#disallowed_sources[@]} > 0 )); then
    echo "FAIL ${CASE}: rust_source_files includes non-root src/kernel files"
    printf '%s\n' "${disallowed_sources[@]}"
    return 1
  fi

  echo "PASS ${CASE}: only src/main.rs is compiled as the kernel crate root"
}

assert_no_kernel_peer_glob() {
  if rg -n 'src/kernel/\*\.rs' "${REPO_ROOT}/Makefile" >/dev/null; then
    echo "FAIL ${CASE}: Makefile still references src/kernel/*.rs glob as build input"
    rg -n 'src/kernel/\*\.rs' "${REPO_ROOT}/Makefile"
    return 1
  fi

  echo "PASS ${CASE}: Makefile does not reference src/kernel/*.rs in Rust source selection"
}

assert_single_kernel_rust_unit() {
  local unit_count
  local -a objects

  mapfile -t objects < <(printf '%s\n' "${RUST_OBJECT_FILES}" | tr ' ' '\n' | rg '.' || true)
  unit_count="${#objects[@]}"

  if (( unit_count != 1 )); then
    echo "FAIL ${CASE}: kernel build emits ${unit_count} Rust objects; expected exactly 1"
    printf '%s\n' "${objects[@]}"
    return 1
  fi

  if ! printf '%s\n' "${objects[0]}" | rg -q "^build/arch/${ARCH}/rust/kernel\\.(o|a)$"; then
    echo "FAIL ${CASE}: kernel Rust object is not kernel.o/kernel.a"
    printf '%s\n' "${objects[0]}"
    return 1
  fi

  echo "PASS ${CASE}: kernel compilation emits one Rust unit: ${objects[0]}"
}

assert_no_kernel_subsystem_output_paths() {
  if printf '%s\n' "${RUST_OBJECT_FILES}" | tr ' ' '\n' | rg "build/arch/${ARCH}/rust/kernel/" >/dev/null; then
    echo "FAIL ${CASE}: found separate Rust outputs for src/kernel/*.rs subsystem paths"
    printf '%s\n' "${RUST_OBJECT_FILES}" | tr ' ' '\n' | rg "build/arch/${ARCH}/rust/kernel/"
    return 1
  fi

  echo "PASS ${CASE}: no subsystem-level kernel Rust object outputs detected"
}

run_case() {
  case "${CASE}" in
    kernel-rust-root-is-single-entry) assert_kernel_root_is_single_entry ;;
    makefile-does-not-glob-src-kernel-peers) assert_no_kernel_peer_glob ;;
    build-produces-single-kernel-rust-unit) assert_single_kernel_rust_unit ;;
    no-kernel-subsystem-rust-objects) assert_no_kernel_subsystem_output_paths ;;
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
  load_make_database || return 1
  load_make_lists || return 1
  describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  run_case
}

main "$@"
