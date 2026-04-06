#!/usr/bin/env bash

qemu_direct_die() {
	echo "error: $*" >&2
	exit 2
}

qemu_direct_repo_root() {
	(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
}

qemu_direct_abs_path() {
	local root
	local path="$1"

	if [[ "${path}" == /* ]]; then
		printf '%s\n' "${path}"
		return 0
	fi

	root="$(qemu_direct_repo_root)"
	printf '%s/%s\n' "${root}" "${path#./}"
}

qemu_direct_container_path() {
	local host_path="$1"
	local root relative

	root="$(qemu_direct_repo_root)"
	relative="${host_path#"${root}/"}"
	[[ "${relative}" != "${host_path}" ]] || qemu_direct_die "path is outside the repo root: ${host_path}"
	printf '/work/%s\n' "${relative}"
}

qemu_direct_container_engine() {
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
	qemu_direct_die "no container engine found (install podman or docker)"
}

qemu_direct_container_mount() {
	local engine="$1"
	local root mount_suffix=""

	root="$(qemu_direct_repo_root)"
	if [[ "${engine}" == "podman" ]]; then
		mount_suffix=":z"
	elif [[ "${engine}" == "docker" ]] && [[ -r /sys/fs/selinux/enforce ]] && [[ "$(cat /sys/fs/selinux/enforce)" == "1" ]]; then
		mount_suffix=":z"
	fi
	printf '%s:/work%s\n' "${root}" "${mount_suffix}"
}

qemu_direct_capture() {
	local log_path="$1"
	local timeout_secs="$2"
	local artifact_mode="$3"
	local artifact_path="$4"
	shift 4
	local -a extra_args=("$@")
	local artifact_path_abs
	local rc
	local -a artifact_args

	artifact_path_abs="$(qemu_direct_abs_path "${artifact_path}")"
	[[ -r "${artifact_path_abs}" ]] || qemu_direct_die "missing artifact: ${artifact_path_abs}"

	if [[ "${log_path}" != "/dev/null" ]]; then
		mkdir -p "$(dirname "${log_path}")"
		rm -f "${log_path}"
	fi

	case "${artifact_mode}" in
	cdrom)
		artifact_args=(-cdrom "${artifact_path_abs}")
		;;
	drive)
		artifact_args=(-drive "format=raw,file=${artifact_path_abs}" -boot order=c)
		;;
	*)
		qemu_direct_die "unsupported artifact mode: ${artifact_mode} (expected: cdrom|drive)"
		;;
	esac

	if command -v qemu-system-i386 >/dev/null 2>&1 && [[ "${KFS_FORCE_CONTAINER_QEMU:-0}" != "1" ]]; then
		set +e
		timeout --foreground "${timeout_secs}" \
			qemu-system-i386 \
			"${artifact_args[@]}" \
			"${extra_args[@]}" \
			</dev/null >"${log_path}" 2>&1
		rc="$?"
		set -e
		printf '%s\n' "${rc}"
		return 0
	fi

	local engine
	local mount_arg
	local -a container_args
	local artifact_path_container
	local -a container_artifact_args

	engine="$(qemu_direct_container_engine)"
	mount_arg="$(qemu_direct_container_mount "${engine}")"
	container_args=("${engine}" run --rm -e KFS_INSIDE_CONTAINER=1 -v "${mount_arg}" -w /work)
	if [[ "${engine}" == "podman" ]]; then
		container_args+=(--userns=keep-id)
	elif [[ "${engine}" == "docker" ]] && ! docker info --format '{{join .SecurityOptions "\n"}}' 2>/dev/null | grep -q '^name=rootless$'; then
		container_args+=(--user "$(id -u):$(id -g)")
	fi

	artifact_path_container="$(qemu_direct_container_path "${artifact_path_abs}")"
	case "${artifact_mode}" in
	cdrom)
		container_artifact_args=(-cdrom "${artifact_path_container}")
		;;
	drive)
		container_artifact_args=(-drive "format=raw,file=${artifact_path_container}" -boot order=c)
		;;
	esac

	set +e
	timeout --foreground "${timeout_secs}" \
		"${container_args[@]}" \
		"kfs1-dev:latest" \
		qemu-system-i386 \
		"${container_artifact_args[@]}" \
		"${extra_args[@]}" \
		</dev/null >"${log_path}" 2>&1
	rc="$?"
	set -e

	printf '%s\n' "${rc}"
}
