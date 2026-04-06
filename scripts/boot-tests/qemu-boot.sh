#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
MODE="${2:-cdrom}"
TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-10}"
PASS_RC="${TEST_PASS_RC:-33}"
FAIL_RC="${TEST_FAIL_RC:-35}"
ISO="build/os-${ARCH}-test.iso"
IMG="build/os-${ARCH}-test.img"
ARTIFACT_OVERRIDE="${KFS_QEMU_BOOT_ARTIFACT:-}"

list_cases() {
	cat <<'EOF'
test-grub-boots-iso
test-grub-boots-img
EOF
}

describe_case() {
	case "$1" in
	test-grub-boots-iso) printf '%s\n' "GRUB boots the generated test ISO artifact" ;;
	test-grub-boots-img) printf '%s\n' "GRUB boots the generated test IMG artifact" ;;
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

artifact_path() {
	case "${MODE}" in
	cdrom)
		printf '%s\n' "${ARTIFACT_OVERRIDE:-${ISO}}"
		;;
	drive)
		printf '%s\n' "${ARTIFACT_OVERRIDE:-${IMG}}"
		;;
	*)
		die "unknown mode: ${MODE} (expected: cdrom|drive)"
		;;
	esac
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
	artifact="$(artifact_path)"
	case "${MODE}" in
	cdrom)
		note "qemu: iso ${artifact}"
		[[ -r "${artifact}" ]] || die "missing ISO: ${artifact}"
		qemu_boot_args=(-cdrom "${artifact}")
		;;
	drive)
		note "qemu: img ${artifact}"
		[[ -r "${artifact}" ]] || die "missing IMG: ${artifact}"
		qemu_boot_args=(-drive "format=raw,file=${artifact}" -boot order=c)
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

main() {
	if [[ "${ARCH}" == "--list" ]]; then
		list_cases
		return 0
	fi

	if [[ "${ARCH}" == "--description" ]]; then
		describe_case "${MODE}"
		return 0
	fi

	run_direct_qemu
}

main "$@"
