#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-tui-manifest-is-complete}"

list_cases() {
	cat <<'EOF'
tui-manifest-is-complete
EOF
}

describe_case() {
	case "$1" in
	tui-manifest-is-complete) printf '%s\n' "test-host publishes a complete TUI manifest before execution" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_complete_manifest() {
	local manifest
	local suite_total
	local declare_total
	local section_sum
	local expected_section

	manifest="$(KFS_TUI_PROTOCOL=1 KFS_COLOR=0 bash scripts/test-host.sh --manifest "${ARCH}")"

	grep -q '^KFS_EVENT|suite|'"${ARCH}"'|[0-9][0-9]*$' <<<"${manifest}" || {
		echo "FAIL ${CASE}: missing suite total event" >&2
		return 1
	}

	if grep -q '^KFS_EVENT|\(section\|start\|result\|summary\)|' <<<"${manifest}"; then
		echo "FAIL ${CASE}: manifest mode must not emit live execution events" >&2
		printf '%s\n' "${manifest}" >&2
		return 1
	fi

	suite_total="$(awk -F'|' '$2 == "suite" { print $4; exit }' <<<"${manifest}")"
	declare_total="$(awk -F'|' '$2 == "declare" { count += 1 } END { print count + 0 }' <<<"${manifest}")"
	section_sum="$(awk -F'|' '$2 == "section_total" { count += $4 } END { print count + 0 }' <<<"${manifest}")"

	[[ "${suite_total}" -gt 0 ]] || {
		echo "FAIL ${CASE}: suite total must be positive" >&2
		return 1
	}

	[[ "${declare_total}" -eq "${suite_total}" ]] || {
		echo "FAIL ${CASE}: suite total (${suite_total}) does not match declare count (${declare_total})" >&2
		return 1
	}

	[[ "${section_sum}" -eq "${suite_total}" ]] || {
		echo "FAIL ${CASE}: section totals (${section_sum}) do not add up to suite total (${suite_total})" >&2
		return 1
	}

	for expected_section in \
		"TOOLCHAIN" \
		"BUILD" \
		"ARTIFACT CHECKS" \
		"HOST UNIT TESTS" \
		"ARCHITECTURE TESTS" \
		"STABILITY TESTS" \
		"REJECTION TESTS" \
		"BOOT TESTS"; do
		awk -F'|' -v section="${expected_section}" '
      $2 == "section_total" && $3 == section { total = $4 + 0 }
      $2 == "declare" && $3 == section { declared += 1 }
      END {
        if (total == "" && declared == 0) {
          exit 2
        }
        if (total != declared) {
          exit 1
        }
      }
    ' <<<"${manifest}"

		case "$?" in
		0) ;;
		1)
			echo "FAIL ${CASE}: section ${expected_section} total does not match declared tests" >&2
			return 1
			;;
		2)
			echo "FAIL ${CASE}: missing manifest entries for section ${expected_section}" >&2
			return 1
			;;
		esac
	done
}

run_case() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

	case "${CASE}" in
	tui-manifest-is-complete)
		assert_complete_manifest
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
