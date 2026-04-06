#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

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

artifact_path() {
	local workdir="$1"
	local kind="$2"

	case "${kind}" in
	kernel) printf '%s/build/kernel-%s.bin\n' "${workdir}" "${ARCH}" ;;
	iso) printf '%s/build/os-%s.iso\n' "${workdir}" "${ARCH}" ;;
	img) printf '%s/build/os-%s.img\n' "${workdir}" "${ARCH}" ;;
	*) die "unknown artifact kind: ${kind}" ;;
	esac
}

copy_workspace() {
	local dst="$1"

	mkdir -p "${dst}"
	cp -a "${REPO_ROOT}/." "${dst}/"
	rm -rf "${dst}/build" "${dst}/.cache" "${dst}/.tmp" "${dst}/.history" "${dst}/node_modules" "${dst}/.venv-test-ui"
}

build_release_artifacts() {
	local workdir="$1"

	(
		cd "${workdir}"
		make clean >/dev/null
		make img >/dev/null
	)
}

compare_artifact() {
	local label="$1"
	local left="$2"
	local right="$3"

	[[ -r "${left}" ]] || die "missing artifact: ${left}"
	[[ -r "${right}" ]] || die "missing artifact: ${right}"

	if cmp -s "${left}" "${right}"; then
		return 0
	fi

	echo "FAIL ${CASE}: ${label} differs" >&2
	sha256sum "${left}" "${right}" >&2
	return 1
}

compare_release_artifacts() {
	local left_root="$1"
	local right_root="$2"

	compare_artifact "kernel-${ARCH}.bin" "$(artifact_path "${left_root}" kernel)" "$(artifact_path "${right_root}" kernel)" || return 1
	compare_artifact "os-${ARCH}.iso" "$(artifact_path "${left_root}" iso)" "$(artifact_path "${right_root}" iso)" || return 1
	compare_artifact "os-${ARCH}.img" "$(artifact_path "${left_root}" img)" "$(artifact_path "${right_root}" img)" || return 1
}

assert_clean_rebuilds_match() {
	local tmp_root workdir first second status

	tmp_root="$(mktemp -d -t kfs-repro-clean.XXXXXX)"
	workdir="${tmp_root}/workspace"
	first="${tmp_root}/first"
	second="${tmp_root}/second"

	status=0
	(
		set -euo pipefail
		copy_workspace "${workdir}"
		build_release_artifacts "${workdir}"
		mkdir -p "${first}"
		cp "$(artifact_path "${workdir}" kernel)" "${first}/kernel.bin"
		cp "$(artifact_path "${workdir}" iso)" "${first}/os.iso"
		cp "$(artifact_path "${workdir}" img)" "${first}/os.img"

		sleep 2

		build_release_artifacts "${workdir}"
		mkdir -p "${second}"
		cp "$(artifact_path "${workdir}" kernel)" "${second}/kernel.bin"
		cp "$(artifact_path "${workdir}" iso)" "${second}/os.iso"
		cp "$(artifact_path "${workdir}" img)" "${second}/os.img"

		compare_artifact "kernel-${ARCH}.bin" "${first}/kernel.bin" "${second}/kernel.bin"
		compare_artifact "os-${ARCH}.iso" "${first}/os.iso" "${second}/os.iso"
		compare_artifact "os-${ARCH}.img" "${first}/os.img" "${second}/os.img"
	) || status=$?
	rm -rf "${tmp_root}"
	return "${status}"
}

assert_workdirs_match() {
	local tmp_root left right status

	tmp_root="$(mktemp -d -t kfs-repro-path.XXXXXX)"

	left="${tmp_root}/work-a"
	right="${tmp_root}/work-b"

	status=0
	(
		set -euo pipefail
		copy_workspace "${left}"
		copy_workspace "${right}"
		build_release_artifacts "${left}"
		build_release_artifacts "${right}"
		compare_release_artifacts "${left}" "${right}"
	) || status=$?
	rm -rf "${tmp_root}"
	return "${status}"
}

run_case() {
	case "${CASE}" in
	release-artifacts-match-across-clean-rebuilds)
		assert_clean_rebuilds_match
		;;
	release-artifacts-match-across-workdirs)
		assert_workdirs_match
		;;
	*)
		die "usage: $0 <arch> {release-artifacts-match-across-clean-rebuilds|release-artifacts-match-across-workdirs}"
		;;
	esac
}

run_host_case() {
	bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
		bash -lc "KFS_HOST_TEST_DIRECT=1 bash scripts/stability-tests/reproducible-builds.sh '${ARCH}' '${CASE}'"
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

	if [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
		run_host_case
		return 0
	fi

	run_case
}

main "$@"
