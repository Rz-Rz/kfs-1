#!/usr/bin/env bash
set -euo pipefail

IMAGE="${KFS_CONTAINER_IMAGE:-kfs1-dev:latest}"
CONTAINERFILE="${KFS_CONTAINERFILE:-Dockerfile}"
USE_KVM="${KFS_USE_KVM:-0}"
ENGINE="${KFS_CONTAINER_ENGINE:-}"
FORCE_BUILD="${KFS_FORCE_IMAGE_BUILD:-0}"
TTY_MODE="${KFS_CONTAINER_TTY:-auto}"

# This prints an error and exits so container commands do not continue in a broken state.
die() {
  echo "error: $*" >&2
  exit 1
}

# This chooses which container engine to use.
# If the user did not force one, it tries Podman first and then Docker.
detect_engine() {
  if [[ -n "${ENGINE}" ]]; then
    command -v "${ENGINE}" >/dev/null 2>&1 || die "KFS_CONTAINER_ENGINE=${ENGINE} not found in PATH"
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
  die "no container engine found (install podman or docker)"
}

# This returns the absolute path to the repository root folder.
repo_root() {
  (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
}

# This builds the correct bind-mount argument for the chosen engine.
# The `:z` suffix is needed on some SELinux setups so the container can read and write the mounted files.
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

# This returns the user mapping flags for the container engine.
# Docker usually needs an explicit user ID so files created in the repo are owned by the current user.
user_args() {
  local engine="$1"
  if [[ "${engine}" == "docker" ]]; then
    echo "--user" "$(id -u):$(id -g)"
    return 0
  fi

  # Rootless Podman typically maps the host user to container root (uid 0).
  # For bind mounts, forcing --user to the host uid can make the repo read-only.
  return 0
}

# This returns the extra flags needed to pass `/dev/kvm` into the container when hardware acceleration is allowed.
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

# This prints the supported subcommands and the main environment variables that change container behavior.
usage() {
  cat <<'EOF'
Usage:
  scripts/container.sh build-image
  scripts/container.sh shell
  scripts/container.sh run -- <command...>
  scripts/container.sh env-check

Env vars:
  KFS_CONTAINER_ENGINE   Force engine: docker|podman
  KFS_CONTAINER_IMAGE    Image tag (default: kfs1-dev:latest)
  KFS_CONTAINERFILE      Build file (default: Dockerfile)
  KFS_USE_KVM=1          Pass through /dev/kvm when available (optional)
  KFS_FORCE_IMAGE_BUILD=1  Rebuild image even if it exists
EOF
}

# This checks whether the chosen container image already exists locally.
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

# This builds the development container image unless an existing image can be reused.
cmd_build_image() {
  local engine
  engine="$(detect_engine)"
  local root
  root="$(repo_root)"

  if [[ "${FORCE_BUILD}" != "1" ]] && image_exists "${engine}"; then
    echo "container: image exists (${IMAGE}); skipping build (set KFS_FORCE_IMAGE_BUILD=1 to rebuild)"
    return 0
  fi

  echo "container: building image ${IMAGE} (engine=${engine})"
  (cd "${root}" && "${engine}" build -t "${IMAGE}" -f "${CONTAINERFILE}" .)
}

# This opens an interactive shell inside the project container.
cmd_shell() {
  local engine
  engine="$(detect_engine)"
  local root
  root="$(repo_root)"

  "${engine}" run --rm -it \
    -v "$(mount_arg "${root}" "${engine}")" \
    -w /work \
    $(user_args "${engine}") \
    $(kvm_args "${engine}") \
    "${IMAGE}" bash
}

# This runs one command inside the project container with the repo mounted at `/work`.
cmd_run() {
  local engine
  engine="$(detect_engine)"
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

# This runs the repo's environment check inside the container so host tool differences do not matter.
cmd_env_check() {
  cmd_run -- bash -lc 'bash scripts/dev-env.sh check'
}

# This reads the requested subcommand and dispatches to the right helper function.
main() {
  local cmd="${1:-}"
  shift || true

  case "${cmd}" in
    build-image) cmd_build_image ;;
    shell) cmd_shell ;;
    run) cmd_run "$@" ;;
    env-check) cmd_env_check ;;
    -h|--help|"") usage; exit 0 ;;
    *) die "unknown command: ${cmd}" ;;
  esac
}

main "$@"
