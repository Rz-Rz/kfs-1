#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
MODE="${2:-cdrom}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
FAIL_RC="${TEST_FAIL_RC:-35}"
ISO="build/os-${ARCH}-test.iso"
IMG="build/os-${ARCH}-test.img"

list_cases() {
	cat <<'EOF'
grub-boots-iso
grub-boots-img
EOF
}

describe_case() {
	case "$1" in
	grub-boots-iso) printf '%s\n' "GRUB boots the ISO artifact" ;;
	grub-boots-img) printf '%s\n' "GRUB boots the IMG artifact" ;;
	*) return 1 ;;
	esac
}

die() {
	echo "error: $*" >&2
	exit 2
}

want_color() {
	[[ -z "${NO_COLOR:-}" ]] || return 1
	[[ "${KFS_COLOR:-}" == "1" ]] && return 0
	[[ -t 1 ]]
}

color() {
	local code="$1"
	if want_color; then
		printf '\033[%sm' "${code}"
	fi
}

reset_color() {
	if want_color; then
		printf '\033[0m'
	fi
}

ok() {
	color "32"
	printf '%s' "$*"
	reset_color
	printf '\n'
}

bad() {
	color "31"
	printf '%s' "$*"
	reset_color
	printf '\n'
}

note() {
	printf '%s\n' "$*"
}

run_direct_qemu() {
	[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

	qemu_kvm_args=()
	qemu_accel="tcg"
	if [[ -e /dev/kvm ]]; then
		qemu_kvm_args+=(-enable-kvm)
		qemu_accel="kvm"
	fi

	note "qemu: arch ${ARCH}"
	note "qemu: mode ${MODE}"
	note "qemu: accel ${qemu_accel}"
	note "qemu: timeout ${TIMEOUT_SECS}s"

	qemu_boot_args=()
	case "${MODE}" in
	cdrom)
		note "qemu: iso ${ISO}"
		[[ -r "${ISO}" ]] || die "missing ISO: ${ISO}"
		qemu_boot_args=(-cdrom "${ISO}")
		;;
	drive)
		note "qemu: img ${IMG}"
		[[ -r "${IMG}" ]] || die "missing IMG: ${IMG}"
		qemu_boot_args=(-drive "format=raw,file=${IMG}" -boot order=c)
		;;
	*)
		die "unknown mode: ${MODE} (expected: cdrom|drive)"
		;;
	esac

	set +e
	timeout --foreground "${TIMEOUT_SECS}" \
		qemu-system-i386 \
		"${qemu_boot_args[@]}" \
		-device isa-debug-exit,iobase=0xf4,iosize=0x04 \
		-nographic \
		-no-reboot \
		-no-shutdown \
		"${qemu_kvm_args[@]}" \
		</dev/null >/dev/null 2>&1
	rc="$?"
	set -e

	if [[ "${rc}" -eq 124 ]]; then
		bad "qemu: FAIL timeout"
		exit 1
	fi
	if [[ "${rc}" -eq "${PASS_RC}" ]]; then
		ok "qemu: PASS"
		exit 0
	fi
	if [[ "${rc}" -eq "${FAIL_RC}" ]]; then
		bad "qemu: FAIL"
		exit 1
	fi

	bad "qemu: FAIL rc=${rc}"
	exit 1
}

run_host_case() {
	case "${MODE}" in
	grub-boots-iso)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make -B iso-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL:-0}' >/dev/null && TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' TEST_PASS_RC='${PASS_RC}' TEST_FAIL_RC='${FAIL_RC}' KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/qemu-boot.sh '${ARCH}' cdrom"
		;;
	grub-boots-img)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "make -B img-test arch='${ARCH}' KFS_TEST_FORCE_FAIL='${KFS_TEST_FORCE_FAIL:-0}' >/dev/null && TEST_TIMEOUT_SECS='${TIMEOUT_SECS}' TEST_PASS_RC='${PASS_RC}' TEST_FAIL_RC='${FAIL_RC}' KFS_HOST_TEST_DIRECT=1 bash scripts/boot-tests/qemu-boot.sh '${ARCH}' drive"
		;;
	*)
		die "unknown host case: ${MODE}"
		;;
	esac
}

main() {
	if [[ "${ARCH}" == "--list" ]]; then
		list_cases
		return 0
	fi

	if [[ "${ARCH}" == "--description" ]]; then
		describe_case "${MODE}"
		return 0
	fi

	if describe_case "${MODE}" >/dev/null 2>&1 && [[ "${KFS_HOST_TEST_DIRECT:-0}" != "1" ]]; then
		run_host_case
		return 0
	fi

	run_direct_qemu
}

main "$@"
