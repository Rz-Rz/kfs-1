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

  local vnc_socket_container qmp_socket_container log_container serial_log_host serial_log_container
  local artifact_path_abs
  local artifact_path_container script_path_host script_path_container
  local build_cmd

  vnc_socket_container="$(qemu_vnc_container_path "${vnc_socket_host}")"
  qmp_socket_container="$(qemu_vnc_container_path "${qmp_socket_host}")"
  artifact_path_abs="$(qemu_vnc_abs_path "${artifact_path}")"
  artifact_path_container="$(qemu_vnc_container_path "${artifact_path_abs}")"
  log_container="$(qemu_vnc_container_path "${log_path}")"
  script_path_host="$(mktemp "$(qemu_vnc_tmp_dir)/qemu-vnc-${case_name}.XXXXXX.sh")"
  script_path_container="$(qemu_vnc_container_path "${script_path_host}")"

  rm -f "${vnc_socket_host}" "${qmp_socket_host}" "${log_path}"
  mkdir -p "$(dirname "${vnc_socket_host}")" "$(dirname "${qmp_socket_host}")" "$(dirname "${log_path}")"

  build_cmd="make -B ${artifact_target} arch='${arch}' >/dev/null"
  if [[ -n "${geometry_preset}" ]]; then
    build_cmd="KFS_SCREEN_GEOMETRY_PRESET='${geometry_preset}' ${build_cmd}"
  fi

  cat >"${script_path_host}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /work
${build_cmd}
rm -f '${vnc_socket_container}' '${qmp_socket_container}' '${log_container}'

qemu-system-i386 \\
  -cdrom '${artifact_path_container}' \\
  -boot d \\
  -display none \\
  -vnc unix:'${vnc_socket_container}',share=force-shared \\
  -qmp unix:'${qmp_socket_container}',server,nowait \\
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
  if [[ -S '${vnc_socket_container}' && -S '${qmp_socket_container}' ]]; then
    break
  fi
  sleep 0.05
done
if ! [[ -S '${vnc_socket_container}' && -S '${qmp_socket_container}' ]]; then
  kill "\${qemu_pid}" >/dev/null 2>&1 || true
  wait "\${qemu_pid}" >/dev/null 2>&1 || true
  echo "FAIL: qemu sockets did not appear after boot in time" >&2
  cat '${log_container}' >&2 || true
  exit 1
fi

timeout --foreground '${timeout_secs}' python3 scripts/boot-tests/lib/vnc_e2e.py \\
  --socket '${vnc_socket_container}' \\
  --qmp-socket '${qmp_socket_container}' \\
  --case '${case_name}' \\
  --timeout-secs '${timeout_secs}'
EOF
  chmod +x "${script_path_host}"

  if bash scripts/with-build-lock.sh bash scripts/container.sh run -- bash "${script_path_container}"; then
    rm -f "${script_path_host}"
    return 0
  fi

  cat "${log_path}" >&2 || true
  rm -f "${script_path_host}"
  return 1
}
