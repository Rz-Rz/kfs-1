#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
QEMU_VNC_LIB="scripts/boot-tests/lib/qemu-vnc.bash"

list_cases() {
	cat <<'EOF'
vnc-e2e-uses-suite-shared-lock
vnc-e2e-generated-runner-uses-detected-repo-root
EOF
}

describe_case() {
	case "$1" in
	vnc-e2e-uses-suite-shared-lock) printf '%s\n' "VNC E2E boot checks use a suite-shared lock outside worker .git directories" ;;
	vnc-e2e-generated-runner-uses-detected-repo-root) printf '%s\n' "VNC E2E generated runner uses the detected repo root instead of hard-coded /work" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

assert_vnc_uses_shared_lock() {
	rg -n 'KFS_VNC_E2E_LOCK_FILE' "${QEMU_VNC_LIB}" >/dev/null ||
		die "missing VNC-specific shared lock override"

	rg -n 'KFS_BUILD_LOCK_FILE="\$\{lock_file\}" bash scripts/with-build-lock\.sh' "${QEMU_VNC_LIB}" >/dev/null ||
		die "VNC launcher does not pass the shared lock into with-build-lock.sh"
}

assert_vnc_uses_detected_repo_root() {
	rg -n "script_workdir=\"\\$\\(qemu_vnc_repo_root\\)\"" "${QEMU_VNC_LIB}" >/dev/null ||
		die "VNC launcher does not set generated script workdir from qemu_vnc_repo_root"

	if rg -n '^cd /work$' "${QEMU_VNC_LIB}" >/dev/null; then
		die "VNC generated script still hard-codes cd /work"
	fi
}

run_case() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

	case "${CASE}" in
	vnc-e2e-uses-suite-shared-lock)
		assert_vnc_uses_shared_lock
		;;
	vnc-e2e-generated-runner-uses-detected-repo-root)
		assert_vnc_uses_detected_repo_root
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
