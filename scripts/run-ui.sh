#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:-i386}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
VNC_SOCKET="${REPO_ROOT}/build/manual-ui-${ARCH}.vnc"
LOG_PATH="${REPO_ROOT}/build/manual-ui-${ARCH}.log"
SOCAT_LOG="/tmp/kfs-manual-ui-socat-${ARCH}.log"
VIEWER_LOG="/tmp/kfs-manual-ui-vncviewer-${ARCH}.log"
TCP_PORT="${KFS_RUN_UI_VNC_PORT:-5905}"

cleanup() {
	kill "${viewer_pid:-}" >/dev/null 2>&1 || true
	wait "${viewer_pid:-}" >/dev/null 2>&1 || true
	kill "${socat_pid:-}" >/dev/null 2>&1 || true
	wait "${socat_pid:-}" >/dev/null 2>&1 || true
	kill "${qemu_pid:-}" >/dev/null 2>&1 || true
	wait "${qemu_pid:-}" >/dev/null 2>&1 || true
	rm -f "${VNC_SOCKET}"
}

trap cleanup EXIT

cd "${REPO_ROOT}"
IMAGE_PATH="build/os-${ARCH}.img"
test -r "${IMAGE_PATH}" || {
	echo "error: missing release IMG: ${IMAGE_PATH} (build it with 'make img arch=${ARCH}')" >&2
	exit 1
}
rm -f "${VNC_SOCKET}" "${LOG_PATH}"

qemu-system-i386 \
	-drive "format=raw,file=${IMAGE_PATH}" \
	-boot order=c \
	-display none \
	-vnc "unix:${VNC_SOCKET},share=force-shared" \
	-monitor none \
	-serial none \
	-parallel none \
	-no-reboot \
	-no-shutdown \
	>"${LOG_PATH}" 2>&1 &
qemu_pid=$!

if ! timeout --foreground 10 bash -lc "until [[ -S \"${VNC_SOCKET}\" ]]; do sleep 0.05; done"; then
	cat "${LOG_PATH}" >&2 || true
	exit 1
fi

socat "TCP-LISTEN:${TCP_PORT},bind=127.0.0.1,reuseaddr,fork" "UNIX-CONNECT:${VNC_SOCKET}" \
	>"${SOCAT_LOG}" 2>&1 &
socat_pid=$!

vncviewer -Shared -SecurityTypes None "127.0.0.1:${TCP_PORT}" >"${VIEWER_LOG}" 2>&1 &
viewer_pid=$!

wait "${viewer_pid}"
