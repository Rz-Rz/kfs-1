#!/usr/bin/env bash
set -euo pipefail

IMAGE="${KFS_CONTAINER_IMAGE:-kfs1-dev:latest}"
CONTAINERFILE="${KFS_CONTAINERFILE:-Dockerfile}"
USE_KVM="${KFS_USE_KVM:-0}"
ENGINE="${KFS_CONTAINER_ENGINE:-}"
FORCE_BUILD="${KFS_FORCE_IMAGE_BUILD:-0}"
TTY_MODE="${KFS_CONTAINER_TTY:-auto}"

die() {
  echo "error: $*" >&2
  exit 1
}

detect_engine_optional() {
  if [[ -n "${ENGINE}" ]]; then
    command -v "${ENGINE}" >/dev/null 2>&1 || return 1
    echo "${ENGINE}"
    return 0
  fi

  if command -v podman >/dev/null 2>&1; then
    echo "podman"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    echo "docker"
    return 0
  fi
  return 1
}

current_env_is_usable() {
  local root
  root="$(repo_root)"
  (
    cd "${root}" &&
      bash scripts/dev-env.sh check >/dev/null 2>&1
  )
}

run_directly_in_current_env() {
  local root
  root="$(repo_root)"
  (
    cd "${root}" &&
      "$@"
  )
}

run_shell_directly_in_current_env() {
  local root
  root="$(repo_root)"
  (
    cd "${root}" &&
      exec bash
  )
}

fallback_to_current_env() {
  current_env_is_usable || die "no container engine found and current environment is missing required tools"
  echo "container: no engine detected; using current environment directly"
}

cmd_shell_without_engine() {
  fallback_to_current_env
  run_shell_directly_in_current_env
}

cmd_run_without_engine() {
  fallback_to_current_env
  if [[ "${1:-}" != "--" ]]; then
    die "run requires -- separator (example: scripts/container.sh run -- make container-env-check)"
  fi
  shift
  if [[ "$#" -eq 0 ]]; then
    die "run requires a command after --"
  fi

  run_directly_in_current_env "$@"
}

cmd_run_gui_without_engine() {
  fallback_to_current_env
  if [[ -z "${DISPLAY:-}" ]]; then
    die "DISPLAY is not set; cannot launch GUI command"
  fi
  if [[ "${1:-}" != "--" ]]; then
    die "run-gui requires -- separator (example: scripts/container.sh run-gui -- make run-ui)"
  fi
  shift
  if [[ "$#" -eq 0 ]]; then
    die "run-gui requires a command after --"
  fi

  run_directly_in_current_env "$@"
}

cmd_env_check_without_engine() {
  fallback_to_current_env
  run_directly_in_current_env bash -lc 'bash scripts/dev-env.sh check'
}

cmd_build_image_without_engine() {
  fallback_to_current_env
  echo "container: skipping image build because the current environment already satisfies the toolchain requirements"
  return 0
}

detect_engine() {
  local engine
  engine="$(detect_engine_optional)" || die "no container engine found (install podman or docker)"
  printf '%s\n' "${engine}"
}

cmd_build_image() {
  local engine
  engine="$(detect_engine_optional)" || {
    cmd_build_image_without_engine
    return 0
  }
  local root
  root="$(repo_root)"

  if [[ "${FORCE_BUILD}" != "1" ]] && image_exists "${engine}"; then
    echo "container: image exists (${IMAGE}); skipping build (set KFS_FORCE_IMAGE_BUILD=1 to rebuild)"
    return 0
  fi

  echo "container: building image ${IMAGE} (engine=${engine})"
  (cd "${root}" && "${engine}" build -t "${IMAGE}" -f "${CONTAINERFILE}" .)
}

cmd_shell() {
  local engine
  engine="$(detect_engine_optional)" || {
    cmd_shell_without_engine
    return 0
  }
  local root
  root="$(repo_root)"

  "${engine}" run --rm -it \
    -v "$(mount_arg "${root}" "${engine}")" \
    -w /work \
    $(user_args "${engine}") \
    $(kvm_args "${engine}") \
    "${IMAGE}" bash
}

cmd_run() {
  local engine
  engine="$(detect_engine_optional)" || {
    cmd_run_without_engine "$@"
    return 0
  }
  local root
  root="$(repo_root)"
  local tty_args=()

  case "${TTY_MODE}" in
    1|true|yes) tty_args=(-t) ;;
    0|false|no) tty_args=() ;;
    auto|"")
      if [[ -t 1 ]]; then
        tty_args=(-t)
      fi
      ;;
    *) die "KFS_CONTAINER_TTY must be auto, 1, or 0" ;;
  esac

  if [[ "${1:-}" != "--" ]]; then
    die "run requires -- separator (example: scripts/container.sh run -- make container-env-check)"
  fi
  shift
  if [[ "$#" -eq 0 ]]; then
    die "run requires a command after --"
  fi

  "${engine}" run --rm \
    "${tty_args[@]}" \
    -v "$(mount_arg "${root}" "${engine}")" \
    -w /work \
    $(user_args "${engine}") \
    $(kvm_args "${engine}") \
    "${IMAGE}" "$@"
}

gui_mount_arg() {
  local source="$1"
  local target="$2"
  local mode="${3:-}"
  local mount_spec

  mount_spec="${source}:${target}"
  if [[ -n "${mode}" ]]; then
    mount_spec="${mount_spec}:${mode}"
  fi

  printf '%s\n' "${mount_spec}"
}

cmd_run_gui() {
  local engine
  engine="$(detect_engine_optional)" || {
    cmd_run_gui_without_engine "$@"
    return 0
  }
  local root
  root="$(repo_root)"
  local tty_args=()
  local gui_args=()
  local security_args=()
  local xauth_host xauth_container

  case "${TTY_MODE}" in
    1|true|yes) tty_args=(-t) ;;
    0|false|no) tty_args=() ;;
    auto|"")
      if [[ -t 1 ]]; then
        tty_args=(-t)
      fi
      ;;
    *) die "KFS_CONTAINER_TTY must be auto, 1, or 0" ;;
  esac

  if [[ -z "${DISPLAY:-}" ]]; then
    die "DISPLAY is not set; cannot launch GUI command"
  fi
  [[ -d /tmp/.X11-unix ]] || die "/tmp/.X11-unix is missing; cannot mount X11 socket"

  if [[ "${1:-}" != "--" ]]; then
    die "run-gui requires -- separator (example: scripts/container.sh run-gui -- make run-ui)"
  fi
  shift
  if [[ "$#" -eq 0 ]]; then
    die "run-gui requires a command after --"
  fi

  xauth_host="${XAUTHORITY:-}"
  xauth_container="/tmp/kfs-host.xauth"
  gui_args=(-e "DISPLAY=${DISPLAY}" -v "$(gui_mount_arg "/tmp/.X11-unix" "/tmp/.X11-unix")")
  if [[ -n "${xauth_host}" && -r "${xauth_host}" ]]; then
    gui_args+=(-e "XAUTHORITY=${xauth_container}")
    gui_args+=(-v "$(gui_mount_arg "${xauth_host}" "${xauth_container}" "ro")")
  fi
  if [[ "${engine}" == "podman" || ( "${engine}" == "docker" && -r /sys/fs/selinux/enforce && "$(cat /sys/fs/selinux/enforce)" == "1" ) ]]; then
    security_args=(--security-opt label=disable)
  fi

  "${engine}" run --rm \
    "${tty_args[@]}" \
    "${security_args[@]}" \
    "${gui_args[@]}" \
    -v "$(mount_arg "${root}" "${engine}")" \
    -w /work \
    $(user_args "${engine}") \
    $(kvm_args "${engine}") \
    "${IMAGE}" "$@"
}

cmd_env_check() {
  local engine
  engine="$(detect_engine_optional)" || {
    cmd_env_check_without_engine
    return 0
  }
  cmd_run -- bash -lc 'bash scripts/dev-env.sh check'
}

repo_root() {
  (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
}

mount_arg() {
  local root="$1"
  local engine="$2"
  if [[ "${engine}" == "podman" ]]; then
    echo "${root}:/work:z"
    return 0
  fi

  if [[ "${engine}" == "docker" && -r /sys/fs/selinux/enforce && "$(cat /sys/fs/selinux/enforce)" == "1" ]]; then
    echo "${root}:/work:z"
    return 0
  fi

  echo "${root}:/work"
}

user_args() {
  local engine="$1"
  if [[ "${engine}" == "docker" ]]; then
    echo "--user" "$(id -u):$(id -g)"
    return 0
  fi

  # Keep bind-mounted artifacts owned by the host user so clean builds work
  # consistently across direct and containerized test runs.
  if [[ "${engine}" == "podman" ]]; then
    echo "--userns=keep-id"
    return 0
  fi

  return 0
}

kvm_args() {
  local engine="$1"
  if [[ "${USE_KVM}" != "1" ]]; then
    return 0
  fi
  if [[ ! -e /dev/kvm ]]; then
    echo "warn: KFS_USE_KVM=1 but /dev/kvm not present; running without KVM" >&2
    return 0
  fi
  echo "--device" "/dev/kvm"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/container.sh build-image
  scripts/container.sh shell
  scripts/container.sh run -- <command...>
  scripts/container.sh run-gui -- <command...>
  scripts/container.sh env-check

Env vars:
  KFS_CONTAINER_ENGINE   Force engine: docker|podman
  KFS_CONTAINER_IMAGE    Image tag (default: kfs1-dev:latest)
  KFS_CONTAINERFILE      Build file (default: Dockerfile)
  KFS_USE_KVM=1          Pass through /dev/kvm when available (optional)
  KFS_FORCE_IMAGE_BUILD=1  Rebuild image even if it exists
EOF
}

image_exists() {
  local engine="$1"
  if [[ "${engine}" == "docker" ]]; then
    "${engine}" image inspect "${IMAGE}" >/dev/null 2>&1
    return $?
  fi
  if "${engine}" image exists "${IMAGE}" >/dev/null 2>&1; then
    return 0
  fi
  "${engine}" image inspect "${IMAGE}" >/dev/null 2>&1
}


main() {
  local cmd="${1:-}"
  shift || true

  case "${cmd}" in
    build-image) cmd_build_image ;;
    shell) cmd_shell ;;
    run) cmd_run "$@" ;;
    run-gui) cmd_run_gui "$@" ;;
    env-check) cmd_env_check ;;
    -h|--help|"") usage; exit 0 ;;
    *) die "unknown command: ${cmd}" ;;
  esac
}

main "$@"
