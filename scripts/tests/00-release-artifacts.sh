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
	local tmp_dir vnc_socket_host qmp_socket_host log_path
	local vnc_socket_container qmp_socket_container log_container artifact_container
	local qemu_boot_args

	tmp_dir="$(mktemp -d "$(qemu_vnc_tmp_dir)/release-boot-${ARCH}-${CASE}.XXXXXX")"
	vnc_socket_host="${tmp_dir}/boot.vnc"
	qmp_socket_host="${tmp_dir}/boot.qmp"
	log_path="${tmp_dir}/boot.log"
	vnc_socket_container="$(qemu_vnc_container_path "${vnc_socket_host}")"
	qmp_socket_container="$(qemu_vnc_container_path "${qmp_socket_host}")"
	log_container="$(qemu_vnc_container_path "${log_path}")"
	artifact_container="$(qemu_vnc_container_path "$(qemu_vnc_abs_path "${artifact}")")"

	case "${qemu_mode}" in
	cdrom)
		qemu_boot_args="-cdrom '${artifact_container}'"
		;;
	drive)
		qemu_boot_args="-drive 'format=raw,file=${artifact_container}' -boot order=c"
		;;
	*)
		rm -rf "${tmp_dir}"
		die "unknown qemu mode: ${qemu_mode}"
		;;
	esac

	bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
		bash -lc "
set -euo pipefail
cd /work
rm -f '${vnc_socket_container}' '${qmp_socket_container}' '${log_container}'

qemu-system-i386 \
  ${qemu_boot_args} \
  -display none \
  -vnc unix:'${vnc_socket_container}',share=force-shared \
  -qmp unix:'${qmp_socket_container}',server,nowait \
  -monitor none \
  -serial none \
  -parallel none \
  -no-reboot \
  -no-shutdown \
  >'${log_container}' 2>&1 &
qemu_pid=\$!

cleanup() {
  if kill -0 \"\${qemu_pid}\" >/dev/null 2>&1; then
    kill \"\${qemu_pid}\" >/dev/null 2>&1 || true
  fi
  wait \"\${qemu_pid}\" >/dev/null 2>&1 || true
}
trap cleanup EXIT

deadline=\$((SECONDS + 12))
while (( SECONDS < deadline )); do
  if [[ -S '${vnc_socket_container}' && -S '${qmp_socket_container}' ]]; then
    break
  fi
  sleep 0.05
done
if ! [[ -S '${vnc_socket_container}' && -S '${qmp_socket_container}' ]]; then
  cat '${log_container}' >&2 || true
  exit 1
fi

timeout --foreground 20 python3 scripts/boot-tests/lib/vnc_e2e.py \
  --socket '${vnc_socket_container}' \
  --qmp-socket '${qmp_socket_container}' \
  --case 'vga-buffer-starts-with-42' \
  --timeout-secs 20
"
	rm -rf "${tmp_dir}"
}

run_host_case() {
	case "${CASE}" in
	release-iso-is-iso9660)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "test -f '${ISO}' && file '${ISO}' | grep -q 'ISO 9660'"
		;;
	release-iso-is-within-10mb)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "test -f '${ISO}' && test \$(wc -c < '${ISO}') -le 10485760"
		;;
	release-iso-boots)
		run_release_boot_case "${ISO}" "cdrom"
		;;
	release-img-is-iso9660)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "test -f '${IMG}' && file '${IMG}' | grep -q 'ISO 9660'"
		;;
	release-img-copies-release-iso)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "test -f '${ISO}' && test -f '${IMG}' && cmp -s '${ISO}' '${IMG}'"
		;;
	release-img-is-within-10mb)
		bash scripts/with-build-lock.sh bash scripts/container.sh run -- \
			bash -lc "test -f '${IMG}' && test \$(wc -c < '${IMG}') -le 10485760"
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
