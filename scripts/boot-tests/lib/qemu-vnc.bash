#!/usr/bin/env bash

set -euo pipefail

qemu_vnc_die() {
	echo "error: $*" >&2
	exit 2
}

qemu_vnc_repo_root() {
	(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
}

qemu_vnc_tmp_dir() {
	local root
	root="$(qemu_vnc_repo_root)"
	mkdir -p "${root}/.tmp"
	printf '%s/.tmp\n' "${root}"
}

qemu_vnc_container_path() {
	local host_path="$1"
	local root relative

	root="$(qemu_vnc_repo_root)"
	relative="${host_path#"${root}/"}"
	[[ "${relative}" != "${host_path}" ]] || qemu_vnc_die "path is outside the repo root: ${host_path}"
	printf '/work/%s\n' "${relative}"
}

qemu_vnc_abs_path() {
	local root
	local path="$1"

	if [[ "${path}" == /* ]]; then
		printf '%s\n' "${path}"
		return 0
	fi

	root="$(qemu_vnc_repo_root)"
	printf '%s/%s\n' "${root}" "${path#./}"
}

qemu_vnc_wait_for_sockets() {
	local timeout_secs="$1"
	local end
	shift
	end="$(($(date +%s) + timeout_secs))"
	while [[ "$(date +%s)" -lt "${end}" ]]; do
		local missing=0
		for path in "$@"; do
			if [[ ! -S "${path}" ]]; then
				missing=1
				break
			fi
		done
		if [[ "${missing}" -eq 0 ]]; then
			return 0
		fi
		sleep 0.05
	done
	return 1
}

qemu_vnc_wait_for_qmp() {
	local timeout_secs="$1"
	local socket_path="$2"
	qemu_vnc_wait_for_sockets "${timeout_secs}" "${socket_path}"
}

qemu_vnc_wait_for_boot() {
	local timeout_secs="$1"
	local vnc_socket="$2"
	qemu_vnc_wait_for_sockets "${timeout_secs}" "${vnc_socket}"
}

qemu_vnc_container_engine() {
	if [[ -n "${KFS_CONTAINER_ENGINE:-}" ]]; then
		printf '%s\n' "${KFS_CONTAINER_ENGINE}"
		return 0
	fi
	if command -v podman >/dev/null 2>&1; then
		printf 'podman\n'
		return 0
	fi
	if command -v docker >/dev/null 2>&1; then
		printf 'docker\n'
		return 0
	fi
	qemu_vnc_die "no container engine found (install podman or docker)"
}

qemu_vnc_container_mount() {
	local engine="$1"
	local root mount_suffix=""

	root="$(qemu_vnc_repo_root)"
	if [[ "${engine}" == "podman" ]]; then
		mount_suffix=":z"
	elif [[ "${engine}" == "docker" ]] && [[ -r /sys/fs/selinux/enforce ]] && [[ "$(cat /sys/fs/selinux/enforce)" == "1" ]]; then
		mount_suffix=":z"
	fi
	printf '%s:/work%s\n' "${root}" "${mount_suffix}"
}

qemu_vnc_container_user_args() {
	local engine="$1"

	if [[ "${engine}" == "podman" ]]; then
		printf '%s\n' "--userns=keep-id"
		return 0
	fi
	if [[ "${engine}" == "docker" ]] && ! docker info --format '{{join .SecurityOptions "\n"}}' 2>/dev/null | grep -q '^name=rootless$'; then
		printf '%s\n' "--user $(id -u):$(id -g)"
	fi
}

qemu_vnc_run_case() {
	local arch="$1"
	local artifact_target="$2"
	local artifact_path="$3"
	local vnc_socket_host="$4"
	local qmp_socket_host="$5"
	local case_name="$6"
	local log_path="$7"
	local timeout_secs="$8"
	local geometry_preset="${9:-}"

	local engine
	local mount_arg
	local -a container_args
	local artifact_path_container
	local log_container
	local artifact_path_abs
	local script_path_host
	local script_path_container
	local vnc_socket_runtime
	local qmp_socket_runtime
	local local_run=0

	artifact_path_abs="$(qemu_vnc_abs_path "${artifact_path}")"
	script_path_host="$(mktemp "$(qemu_vnc_tmp_dir)/qemu-vnc-${case_name}.XXXXXX.sh")"
	[[ -r "${artifact_path_abs}" ]] || qemu_vnc_die "missing artifact: ${artifact_path_abs}"
	[[ "${artifact_target}" == "iso" || "${artifact_target}" == "img" ]] || qemu_vnc_die "unsupported artifact target: ${artifact_target}"
	vnc_socket_runtime="/tmp/kfs-vnc-${arch}-$$-$RANDOM.sock"
	qmp_socket_runtime="/tmp/kfs-qmp-${arch}-$$-$RANDOM.sock"

	rm -f "${vnc_socket_host}" "${qmp_socket_host}" "${log_path}"
	mkdir -p "$(dirname "${vnc_socket_host}")" "$(dirname "${qmp_socket_host}")" "$(dirname "${log_path}")"

	if [[ "${KFS_INSIDE_CONTAINER:-0}" == "1" || ( -x "$(command -v qemu-system-i386 2>/dev/null)" && "${KFS_FORCE_CONTAINER_QEMU:-0}" != "1" ) ]]; then
		local_run=1
		artifact_path_container="${artifact_path_abs}"
		log_container="${log_path}"
	else
		engine="$(qemu_vnc_container_engine)"
		mount_arg="$(qemu_vnc_container_mount "${engine}")"
		container_args=("${engine}" run --rm -e KFS_INSIDE_CONTAINER=1 -v "${mount_arg}" -w /work)
		if [[ "${engine}" == "podman" ]]; then
			container_args+=(--userns=keep-id)
		elif [[ "${engine}" == "docker" ]] && ! docker info --format '{{join .SecurityOptions "\n"}}' 2>/dev/null | grep -q '^name=rootless$'; then
			container_args+=(--user "$(id -u):$(id -g)")
		fi
		artifact_path_container="$(qemu_vnc_container_path "${artifact_path_abs}")"
		script_path_container="$(qemu_vnc_container_path "${script_path_host}")"
		log_container="$(qemu_vnc_container_path "${log_path}")"
	fi

	cat >"${script_path_host}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /work
rm -f '${vnc_socket_runtime}' '${qmp_socket_runtime}' '${log_container}'

qemu-system-i386 \\
  -cdrom '${artifact_path_container}' \\
  -boot d \\
  -display none \\
  -vnc unix:'${vnc_socket_runtime}',share=force-shared \\
  -qmp unix:'${qmp_socket_runtime}',server,nowait \\
  -monitor none \\
  -serial none \\
  -parallel none \\
  -no-reboot \\
  -no-shutdown \\
  >'${log_container}' 2>&1 &
qemu_pid=\$!

cleanup() {
  if kill -0 "\${qemu_pid}" >/dev/null 2>&1; then
    kill "\${qemu_pid}" >/dev/null 2>&1 || true
  fi
  wait "\${qemu_pid}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready_deadline=\$((SECONDS + 12))
while (( SECONDS < ready_deadline )); do
  if [[ -S '${vnc_socket_runtime}' && -S '${qmp_socket_runtime}' ]]; then
    break
  fi
  sleep 0.05
done
if ! [[ -S '${vnc_socket_runtime}' && -S '${qmp_socket_runtime}' ]]; then
  kill "\${qemu_pid}" >/dev/null 2>&1 || true
  wait "\${qemu_pid}" >/dev/null 2>&1 || true
  echo "FAIL: qemu sockets did not appear after boot in time" >&2
  cat '${log_container}' >&2 || true
  exit 1
fi

timeout --foreground '${timeout_secs}' python3 scripts/boot-tests/lib/vnc_e2e.py \\
  --socket '${vnc_socket_runtime}' \\
  --qmp-socket '${qmp_socket_runtime}' \\
  --case '${case_name}' \\
  --timeout-secs '${timeout_secs}'
EOF
	chmod +x "${script_path_host}"

	if (( local_run )); then
		if bash scripts/with-build-lock.sh bash "${script_path_host}"; then
			rm -f "${script_path_host}"
			return 0
		fi
	elif bash scripts/with-build-lock.sh "${container_args[@]}" "kfs1-dev:latest" bash "${script_path_container}"; then
		rm -f "${script_path_host}"
		return 0
	fi

	cat "${log_path}" >&2 || true
	rm -f "${script_path_host}"
	return 1
}
