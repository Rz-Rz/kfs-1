#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

list_cases() {
  cat <<'EOF'
architecture-section-present-in-manifest
architecture-section-order-is-stable
tui-recognizes-architecture-section
architecture-panel-label-is-arch
architecture-panel-title-is-updated
exports-allowlist-file-is-non-empty
EOF
}

describe_case() {
  case "$1" in
    architecture-section-present-in-manifest) printf '%s\n' "manifest publishes the architecture test section" ;;
    architecture-section-order-is-stable) printf '%s\n' "manifest keeps architecture tests between unit tests and stability tests" ;;
    tui-recognizes-architecture-section) printf '%s\n' "TUI recognizes ARCHITECTURE TESTS as a first-class section" ;;
    architecture-panel-label-is-arch) printf '%s\n' "TUI renders ARCH as the architecture section label" ;;
    architecture-panel-title-is-updated) printf '%s\n' "TUI panel title includes architecture" ;;
    exports-allowlist-file-is-non-empty) printf '%s\n' "architecture export allowlist exists and is non-empty" ;;
    *) return 1 ;;
  esac
}

die() {
  echo "error: $*" >&2
  exit 2
}

manifest_output() {
  KFS_TUI_PROTOCOL=1 KFS_COLOR=0 bash scripts/test-host.sh --manifest "${ARCH}"
}

assert_architecture_section_present() {
  local manifest
  manifest="$(manifest_output)"

  grep -q '^KFS_EVENT|section_total|ARCHITECTURE TESTS|[1-9][0-9]*$' <<<"${manifest}" || {
    echo "FAIL ${CASE}: missing non-zero ARCHITECTURE TESTS section_total"
    printf '%s\n' "${manifest}" >&2
    return 1
  }

  grep -q '^KFS_EVENT|declare|ARCHITECTURE TESTS|' <<<"${manifest}" || {
    echo "FAIL ${CASE}: missing ARCHITECTURE TESTS declare entry"
    printf '%s\n' "${manifest}" >&2
    return 1
  }
}

assert_architecture_section_order() {
  local manifest tests_line arch_line stability_line
  manifest="$(manifest_output)"
  tests_line="$(grep -n '^KFS_EVENT|section_total|TESTS|' <<<"${manifest}" | cut -d: -f1)"
  arch_line="$(grep -n '^KFS_EVENT|section_total|ARCHITECTURE TESTS|' <<<"${manifest}" | cut -d: -f1)"
  stability_line="$(grep -n '^KFS_EVENT|section_total|STABILITY TESTS|' <<<"${manifest}" | cut -d: -f1)"

  [[ -n "${tests_line}" && -n "${arch_line}" && -n "${stability_line}" ]] || {
    echo "FAIL ${CASE}: missing section_total ordering markers"
    return 1
  }

  [[ "${tests_line}" -lt "${arch_line}" && "${arch_line}" -lt "${stability_line}" ]] || {
    echo "FAIL ${CASE}: architecture section order drifted"
    return 1
  }
}

assert_tui_knows_architecture_section() {
  rg -n 'ARCHITECTURE TESTS' scripts/kfs_tui.py >/dev/null || {
    echo "FAIL ${CASE}: scripts/kfs_tui.py does not reference ARCHITECTURE TESTS"
    return 1
  }
}

assert_architecture_panel_label() {
  rg -n 'SECTION_LABELS = \{' -A8 scripts/kfs_tui.py | grep -q '"ARCHITECTURE TESTS": "ARCH"' || {
    echo "FAIL ${CASE}: missing ARCH section label in TUI"
    return 1
  }
}

assert_architecture_panel_title() {
  rg -n 'PANEL_TITLES = \[' -A4 scripts/kfs_tui.py | grep -q 'ARCHITECTURE / STABILITY / REJECTION' || {
    echo "FAIL ${CASE}: missing architecture panel title"
    return 1
  }
}

assert_allowlist_exists() {
  [[ -s "scripts/architecture-tests/fixtures/exports.${ARCH}.allowlist" ]] || {
    echo "FAIL ${CASE}: missing or empty export allowlist"
    return 1
  }
}

run_case() {
  [[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

  case "${CASE}" in
    architecture-section-present-in-manifest)
      assert_architecture_section_present
      ;;
    architecture-section-order-is-stable)
      assert_architecture_section_order
      ;;
    tui-recognizes-architecture-section)
      assert_tui_knows_architecture_section
      ;;
    architecture-panel-label-is-arch)
      assert_architecture_panel_label
      ;;
    architecture-panel-title-is-updated)
      assert_architecture_panel_title
      ;;
    exports-allowlist-file-is-non-empty)
      assert_allowlist_exists
      ;;
    *)
      die "unknown case: ${CASE}"
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

  describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
  run_case
}

main "$@"
