#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
DOCKERFILE="Dockerfile"

list_cases() {
	cat <<'EOF'
dockerfile-pins-base-and-tool-versions
EOF
}

describe_case() {
	case "$1" in
	dockerfile-pins-base-and-tool-versions) printf '%s\n' "Dockerfile pins the base image digest and toolchain versions" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_pattern() {
	local pattern="$1"
	local label="$2"

	rg -n "${pattern}" "${DOCKERFILE}" >/dev/null ||
		die "missing ${label} in ${DOCKERFILE}"
}

run_case() {
	case "${CASE}" in
	dockerfile-pins-base-and-tool-versions)
		assert_pattern '^FROM ubuntu:22\.04@sha256:' 'pinned Ubuntu base image digest'
		assert_pattern '^ARG RUST_TOOLCHAIN=' 'pinned Rust toolchain version'
		assert_pattern '^ARG RUFF_VERSION=' 'pinned ruff version'
		assert_pattern '^ARG BLACK_VERSION=' 'pinned black version'
		;;
	*)
		die "usage: $0 <arch> {dockerfile-pins-base-and-tool-versions}"
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
	describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
	run_case
}

main "$@"
