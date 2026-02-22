#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
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

need_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "missing required tool: ${cmd}"
}

cmd_check() {
  echo "dev-env: checking required tools..."
  need_cmd bash
  need_cmd make
  need_cmd timeout
  need_cmd ld
  need_cmd readelf
  need_cmd objdump
  need_cmd nm
  need_cmd nasm

  need_cmd grub-mkrescue
  need_cmd xorriso
  need_cmd mtools

  need_cmd qemu-system-i386

  printf '%s ' "dev-env:"
  ok "OK"
  echo "  nasm: $(nasm -v | head -n 1)"
  echo "  ld: $(ld -v | head -n 1)"
  echo "  grub-mkrescue: $(grub-mkrescue --version | head -n 1)"
  echo "  qemu-system-i386: $(qemu-system-i386 --version | head -n 1)"
  echo "  xorriso: $(xorriso -version 2>/dev/null | head -n 1)"
}

cmd_install_hint() {
  cat <<'EOF'
This repo's canonical workflow uses the container toolchain (recommended):
  make container-image
  make container-env-check

If you still want to install tools natively, you need at least:
  nasm, qemu-system-i386, grub-mkrescue, xorriso, mtools, make, binutils
EOF
}

usage() {
  cat <<'EOF'
Usage:
  scripts/dev-env.sh check
  scripts/dev-env.sh install-hint
EOF
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    check) cmd_check ;;
    install-hint) cmd_install_hint ;;
    -h|--help|"") usage; exit 0 ;;
    *) die "unknown command: ${cmd}" ;;
  esac
}

main "$@"
