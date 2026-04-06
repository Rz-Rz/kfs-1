#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
# shellcheck disable=SC2034
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
LOG="build/m5-string-runtime-${CASE}.log"
INIT_SOURCE="src/kernel/core/init.rs"
source "$(dirname "${BASH_SOURCE[0]}")/lib/qemu-direct.bash"

list_cases() {
	cat <<'EOF'
release-core-init-calls-string-strlen
runtime-confirms-strlen
release-core-init-calls-string-strcmp
runtime-confirms-strcmp
runtime-confirms-string-helpers
runtime-string-markers-are-ordered
EOF
}

describe_case() {
	case "$1" in
	release-core-init-calls-string-strlen) printf '%s\n' "release core init calls string::strlen in the string sanity path" ;;
	runtime-confirms-strlen) printf '%s\n' "runtime emits STRLEN_OK" ;;
	release-core-init-calls-string-strcmp) printf '%s\n' "release core init calls string::strcmp in the string sanity path" ;;
	runtime-confirms-strcmp) printf '%s\n' "runtime emits STRCMP_OK" ;;
	runtime-confirms-string-helpers) printf '%s\n' "runtime emits STRING_HELPERS_OK" ;;
	runtime-string-markers-are-ordered) printf '%s\n' "runtime emits STRLEN_OK then STRCMP_OK then STRING_HELPERS_OK in order" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

iso_path() {
	printf 'build/os-%s-test.iso\n' "${ARCH}"
}

find_pattern() {
	local pattern="$1"
	shift

	if command -v rg >/dev/null 2>&1; then
		rg -n "${pattern}" -S "$@" >/dev/null
	else
		grep -En "${pattern}" "$@" >/dev/null
	fi
}

assert_pattern() {
	local pattern="$1"
	local label="$2"
	shift 2

	if ! find_pattern "${pattern}" "$@"; then
		echo "FAIL src: missing ${label}"
		return 1
	fi

	echo "PASS src: ${label}"
	return 0
}

assert_pattern_absent() {
	local pattern="$1"
	local label="$2"
	shift 2

	if find_pattern "${pattern}" "$@"; then
		echo "FAIL src: unexpected ${label}"
		return 1
	fi

	echo "PASS src: ${label} absent"
	return 0
}

run_qemu_capture() {
	local iso
	local rc
	iso="$(iso_path)"
	[[ -r "${iso}" ]] || die "missing ISO: ${iso} (build it with make test-artifacts arch=${ARCH})"

	rc="$(
		qemu_direct_capture "${LOG}" "${TIMEOUT_SECS}" cdrom "${iso}" \
			-device isa-debug-exit,iobase=0xf4,iosize=0x04 \
			-serial stdio \
			-display none \
			-monitor none \
			-no-reboot \
			-no-shutdown
	)"

	if [[ "${rc}" -ne "${PASS_RC}" ]]; then
		echo "FAIL ${CASE}: expected PASS rc=${PASS_RC}, got rc=${rc}" >&2
		cat "${LOG}" >&2
		exit 1
	fi
}

assert_log_contains() {
	local token="$1"
	if ! grep -qFx "${token}" "${LOG}"; then
		echo "FAIL ${CASE}: missing runtime marker ${token}" >&2
		cat "${LOG}" >&2
		exit 1
	fi
}

assert_log_order() {
	local previous_line=0
	local token
	local line

	for token in "$@"; do
		line="$(grep -nFx "${token}" "${LOG}" | head -n 1 | cut -d: -f1)"
		[[ -n "${line}" ]] || {
			echo "FAIL ${CASE}: missing runtime marker ${token}" >&2
			cat "${LOG}" >&2
			exit 1
		}

		if ((line <= previous_line)); then
			echo "FAIL ${CASE}: runtime marker ${token} is out of order" >&2
			cat "${LOG}" >&2
			exit 1
		fi

		previous_line="${line}"
	done
}

run_direct_case() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	run_qemu_capture

	case "${CASE}" in
	release-core-init-calls-string-strlen)
		assert_pattern 'string::strlen\(' 'string::strlen call in core init' "${INIT_SOURCE}"
		assert_pattern_absent '\bkfs_strlen\(' 'kfs_strlen call in core init' "${INIT_SOURCE}"
		assert_log_contains "STRLEN_OK"
		;;
	runtime-confirms-strlen)
		assert_log_contains "STRLEN_OK"
		;;
	release-core-init-calls-string-strcmp)
		assert_pattern 'string::strcmp\(' 'string::strcmp call in core init' "${INIT_SOURCE}"
		assert_pattern_absent '\bkfs_strcmp\(' 'kfs_strcmp call in core init' "${INIT_SOURCE}"
		assert_log_contains "STRCMP_OK"
		;;
	runtime-confirms-strcmp)
		assert_log_contains "STRCMP_OK"
		;;
	runtime-confirms-string-helpers)
		assert_log_contains "STRING_HELPERS_OK"
		;;
	runtime-string-markers-are-ordered)
		assert_log_order "STRLEN_OK" "STRCMP_OK" "STRING_HELPERS_OK"
		;;
	*)
		die "usage: $0 <arch> {release-core-init-calls-string-strlen|runtime-confirms-strlen|release-core-init-calls-string-strcmp|runtime-confirms-strcmp|runtime-confirms-string-helpers|runtime-string-markers-are-ordered}"
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

	run_direct_case
}

main "$@"
