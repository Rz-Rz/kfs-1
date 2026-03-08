#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
TEST_SOURCE="tests/host_string.rs"
SOURCE_CRATE="src/kernel/string.rs"
SOURCE_IMPL="src/kernel/string/string_impl.rs"

list_cases() {
  cat <<'EOF'
host-strlen-unit-tests-pass
host-strcmp-unit-tests-pass
rust-defines-strlen
rust-defines-strcmp
rust-avoids-extern-strlen
rust-avoids-extern-strcmp
release-kernel-links-string-helper-marker
EOF
}

describe_case() {
  case "$1" in
    host-strlen-unit-tests-pass) printf '%s\n' "host strlen unit tests pass" ;;
    host-strcmp-unit-tests-pass) printf '%s\n' "host strcmp unit tests pass" ;;
    rust-defines-strlen) printf '%s\n' "Rust defines strlen in the kernel helper module" ;;
    rust-defines-strcmp) printf '%s\n' "Rust defines strcmp in the kernel helper module" ;;
    rust-avoids-extern-strlen) printf '%s\n' "kernel helper module does not fall back to extern strlen" ;;
    rust-avoids-extern-strcmp) printf '%s\n' "kernel helper module does not fall back to extern strcmp" ;;
    release-kernel-links-string-helper-marker) printf '%s\n' "release kernel links kfs_string_helpers_marker" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

ensure_sources_exist() {
  [[ -r "${TEST_SOURCE}" ]] || die "missing host unit test source: ${TEST_SOURCE}"
  [[ -r "${SOURCE_CRATE}" ]] || die "missing string helper crate: ${SOURCE_CRATE}"
  [[ -r "${SOURCE_IMPL}" ]] || die "missing string helper implementation: ${SOURCE_IMPL}"
}

find_string_pattern() {
  local pattern="$1"

  if command -v rg >/dev/null 2>&1; then
    rg -n "${pattern}" -S "${SOURCE_CRATE}" "${SOURCE_IMPL}" >/dev/null
  else
    grep -En "${pattern}" "${SOURCE_CRATE}" "${SOURCE_IMPL}" >/dev/null
  fi
}

assert_string_pattern() {
  local pattern="$1"
  local label="$2"

  if ! find_string_pattern "${pattern}"; then
    echo "FAIL src: missing ${label}"
    return 1
  fi

  echo "PASS src: ${label}"
  return 0
}

assert_no_string_pattern() {
  local pattern="$1"
  local label="$2"

  if find_string_pattern "${pattern}"; then
    echo "FAIL src: found ${label}"
    if command -v rg >/dev/null 2>&1; then
      rg -n "${pattern}" -S "${SOURCE_CRATE}" "${SOURCE_IMPL}" || true
    else
      grep -En "${pattern}" "${SOURCE_CRATE}" "${SOURCE_IMPL}" || true
    fi
    return 1
  fi

  echo "PASS src: ${label}"
  return 0
}

run_host_tests() {
  local filter="$1"
  local test_bin="build/ut_string_${filter%_}"

  bash scripts/container.sh run -- \
    bash -lc "mkdir -p build && rustc --test -o '${test_bin}' '${TEST_SOURCE}' >/dev/null && '${test_bin}' '${filter}'"
}

assert_release_marker_symbol() {
  bash scripts/container.sh run -- \
    bash -lc "make -B all arch='${ARCH}' >/dev/null && nm -n 'build/kernel-${ARCH}.bin' | grep -qE '[[:space:]]T[[:space:]]+kfs_string_helpers_marker$'"

  echo "PASS build/kernel-${ARCH}.bin: kfs_string_helpers_marker"
}

run_direct_case() {
  ensure_sources_exist

  case "${CASE}" in
    host-strlen-unit-tests-pass)
      run_host_tests 'strlen_'
      ;;
    host-strcmp-unit-tests-pass)
      run_host_tests 'strcmp_'
      ;;
    rust-defines-strlen)
      assert_string_pattern '\bfn[[:space:]]+strlen\b' 'strlen definition'
      ;;
    rust-defines-strcmp)
      assert_string_pattern '\bfn[[:space:]]+strcmp\b' 'strcmp definition'
      ;;
    rust-avoids-extern-strlen)
      assert_no_string_pattern 'extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+strlen\b' 'extern strlen fallback'
      ;;
    rust-avoids-extern-strcmp)
      assert_no_string_pattern 'extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+strcmp\b' 'extern strcmp fallback'
      ;;
    release-kernel-links-string-helper-marker)
      assert_release_marker_symbol
      ;;
    *)
      die "usage: $0 <arch> {host-strlen-unit-tests-pass|host-strcmp-unit-tests-pass|rust-defines-strlen|rust-defines-strcmp|rust-avoids-extern-strlen|rust-avoids-extern-strcmp|release-kernel-links-string-helper-marker}"
      ;;
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
  run_direct_case
}

main "$@"
