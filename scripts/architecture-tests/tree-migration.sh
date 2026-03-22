#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

list_cases() {
  cat <<'EOF'
future-architecture-tree-artifacts-exist
EOF
}

describe_case() {
  case "$1" in
    future-architecture-tree-artifacts-exist) printf '%s\n' "all required future-architecture tree artifacts exist" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

required_tree_artifacts() {
  cat <<'EOF'
src/main.rs
src/freestanding/mod.rs
src/freestanding/panic.rs
src/freestanding/section_markers.rs
src/kernel/mod.rs
src/kernel/core/entry.rs
src/kernel/core/init.rs
src/kernel/machine/port.rs
src/kernel/types/range.rs
src/kernel/types/screen.rs
src/kernel/klib/string/mod.rs
src/kernel/klib/string/imp.rs
src/kernel/klib/memory/mod.rs
src/kernel/klib/memory/imp.rs
src/kernel/drivers/serial/mod.rs
src/kernel/drivers/vga_text/mod.rs
src/kernel/drivers/vga_text/writer.rs
src/kernel/services/diagnostics.rs
src/kernel/services/console.rs
EOF
}

assert_tree_artifacts_exist() {
  local missing=()
  local path

  while IFS= read -r path; do
    [[ -f "${REPO_ROOT}/${path}" ]] || missing+=("${path}")
  done < <(required_tree_artifacts)

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "FAIL ${CASE}: missing required future tree artifacts"
    printf '%s\n' "${missing[@]}"
    return 1
  fi

  echo "PASS ${CASE}: all required future tree artifacts exist"
}
run_case() {
  case "${CASE}" in
    future-architecture-tree-artifacts-exist) assert_tree_artifacts_exist ;;
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
