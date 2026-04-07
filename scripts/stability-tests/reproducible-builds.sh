#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

die() {
	echo "error: $*" >&2
	exit 2
}

list_cases() {
	cat <<'EOF'
release-artifacts-match-across-clean-rebuilds
release-artifacts-match-across-workdirs
EOF
}

describe_case() {
	case "$1" in
	release-artifacts-match-across-clean-rebuilds) printf '%s\n' "release kernel/ISO/IMG stay byte-identical across clean rebuilds" ;;
	release-artifacts-match-across-workdirs) printf '%s\n' "release kernel/ISO/IMG stay byte-identical across copied workdirs" ;;
	*) return 1 ;;
	esac
}

run_case() {
	local stamp=""
	case "${CASE}" in
	release-artifacts-match-across-clean-rebuilds)
		stamp="build/reproducible/${ARCH}-release-artifacts-match-across-clean-rebuilds.stamp"
		;;
	release-artifacts-match-across-workdirs)
		stamp="build/reproducible/${ARCH}-release-artifacts-match-across-workdirs.stamp"
		;;
	*)
		die "usage: $0 <arch> {release-artifacts-match-across-clean-rebuilds|release-artifacts-match-across-workdirs}"
		;;
	esac

	[[ -r "${stamp}" ]] || die "missing reproducibility proof: ${stamp} (build it with make reproducible-builds arch=${ARCH})"
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
