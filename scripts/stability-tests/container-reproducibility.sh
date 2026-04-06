#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
DOCKERFILE="Dockerfile"

list_cases() {
	cat <<'EOF'
dockerfile-pins-ubuntu-apt-snapshot
EOF
}

describe_case() {
	case "$1" in
	dockerfile-pins-ubuntu-apt-snapshot) printf '%s\n' "Dockerfile pins Ubuntu apt sources to a fixed snapshot timestamp" ;;
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
	dockerfile-pins-ubuntu-apt-snapshot)
		assert_pattern '^ARG UBUNTU_SNAPSHOT=[0-9]{8}T[0-9]{6}Z$' 'fixed UBUNTU_SNAPSHOT arg'
		assert_pattern '^ARG UBUNTU_CA_CERTIFICATES_VERSION=' 'pinned ca-certificates bootstrap version'
		assert_pattern '^ARG UBUNTU_CA_CERTIFICATES_SHA256=' 'pinned ca-certificates bootstrap checksum'
		assert_pattern 'ADD https://snapshot\.ubuntu\.com/ubuntu/\$\{UBUNTU_SNAPSHOT\}/pool/main/c/ca-certificates/' 'snapshot-pinned bootstrap deb'
		assert_pattern 'sha256sum -c -' 'checksum verification for bootstrap deb'
		assert_pattern 'snapshot\.ubuntu\.com/ubuntu/\$\{UBUNTU_SNAPSHOT\}/' 'direct snapshot apt source rewrite'
		;;
	*)
		die "usage: $0 <arch> {dockerfile-pins-ubuntu-apt-snapshot}"
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
