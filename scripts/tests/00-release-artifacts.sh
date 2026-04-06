#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
CASE="${2:-}"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${REPO_ROOT}/scripts/boot-tests/lib/qemu-vnc.bash"

ISO="build/os-${ARCH}.iso"
IMG="build/os-${ARCH}.img"

list_cases() {
	cat <<'EOF'
release-iso-is-iso9660
release-iso-is-within-10mb
release-iso-boots
release-img-is-iso9660
release-img-copies-release-iso
release-img-is-within-10mb
release-img-boots
EOF
}

describe_case() {
	case "$1" in
	release-iso-is-iso9660) printf '%s\n' "canonical release ISO is an ISO9660 image" ;;
	release-iso-is-within-10mb) printf '%s\n' "canonical release ISO stays within the 10 MB upper bound" ;;
	release-iso-boots) printf '%s\n' "canonical release ISO boots via GRUB in QEMU" ;;
	release-img-is-iso9660) printf '%s\n' "canonical release IMG is an ISO9660 image" ;;
	release-img-copies-release-iso) printf '%s\n' "canonical release IMG matches the release ISO bytes" ;;
	release-img-is-within-10mb) printf '%s\n' "canonical release IMG stays within the 10 MB upper bound" ;;
	release-img-boots) printf '%s\n' "canonical release IMG boots via GRUB in QEMU" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

run_release_boot_case() {
	local artifact="$1"
	local qemu_mode="$2"
	local artifact_target
	local tmp_dir log_path qemu_vnc_mode

	tmp_dir="$(mktemp -d "$(qemu_vnc_tmp_dir)/release-boot-${ARCH}-${CASE}.XXXXXX")"
	log_path="${tmp_dir}/boot.log"

	case "${qemu_mode}" in
	cdrom)
		artifact_target="iso"
		qemu_vnc_mode="vga-buffer-starts-with-42"
		;;
	drive)
		artifact_target="img"
		qemu_vnc_mode="vga-buffer-starts-with-42"
		;;
	*)
		rm -rf "${tmp_dir}"
		die "unknown qemu mode: ${qemu_mode}"
		;;
	esac

	qemu_vnc_run_case "${ARCH}" "${artifact_target}" "${artifact}" "${tmp_dir}/boot.vnc" "${tmp_dir}/boot.qmp" "${qemu_vnc_mode}" "${log_path}" 20
	rm -rf "${tmp_dir}"
}

run_host_case() {
	case "${CASE}" in
	release-iso-is-iso9660)
		bash scripts/with-build-lock.sh bash -lc "test -f '${ISO}' && file '${ISO}' | grep -q 'ISO 9660'"
		;;
	release-iso-is-within-10mb)
		bash scripts/with-build-lock.sh bash -lc "test -f '${ISO}' && test \$(wc -c < '${ISO}') -le 10485760"
		;;
	release-iso-boots)
		run_release_boot_case "${ISO}" "cdrom"
		;;
	release-img-is-iso9660)
		bash scripts/with-build-lock.sh bash -lc "test -f '${IMG}' && file '${IMG}' | grep -q 'ISO 9660'"
		;;
	release-img-copies-release-iso)
		bash scripts/with-build-lock.sh bash -lc "test -f '${ISO}' && test -f '${IMG}' && cmp -s '${ISO}' '${IMG}'"
		;;
	release-img-is-within-10mb)
		bash scripts/with-build-lock.sh bash -lc "test -f '${IMG}' && test \$(wc -c < '${IMG}') -le 10485760"
		;;
	release-img-boots)
		run_release_boot_case "${IMG}" "drive"
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

	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"
	describe_case "${CASE}" >/dev/null 2>&1 || die "unknown case: ${CASE}"
	run_host_case
}

main "$@"
