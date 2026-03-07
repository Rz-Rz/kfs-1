#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
  cat <<'EOF'
build-iso
build-img-artifact
EOF
}

describe_case() {
  case "$1" in
    build-iso) printf '%s\n' "build the ISO artifact" ;;
    build-img-artifact) printf '%s\n' "build the IMG artifact" ;;
    *) return 1 ;;
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

  case "${CASE}" in
    build-iso)
      bash scripts/container.sh run -- \
        bash -lc "make -B iso-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL:-0}' >/dev/null"
      ;;
    build-img-artifact)
      bash scripts/container.sh run -- \
        bash -lc "make -B img-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL:-0}' >/dev/null"
      ;;
    *)
      echo "error: usage: $0 <arch> {build-iso|build-img-artifact}" >&2
      exit 2
      ;;
  esac
}

main "$@"
