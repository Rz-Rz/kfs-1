#!/usr/bin/env bash
set -euo pipefail

MODE="run"
ARCH="${1:-i386}"
VERBOSE="${KFS_VERBOSE:-0}"
TUI_PROTOCOL="${KFS_TUI_PROTOCOL:-0}"
SKIP_TUI_MANIFEST="${KFS_TUI_SKIP_MANIFEST:-0}"
SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${ARCH}" == "--manifest" ]]; then
  MODE="manifest"
  ARCH="${2:-i386}"
fi

die() {
  echo "error: $*" >&2
  exit 2
}

is_tty() {
  [[ -t 1 ]]
}

want_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ "${KFS_COLOR:-}" == "1" ]] && return 0
  is_tty
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

hr() {
  printf '%s\n' "============================================================"
}

banner() {
  local title="$1"
  hr
  color "1;34"
  printf '%s\n' "${title}"
  reset_color
  hr
}

info() {
  color "2"
  printf '%s' "$*"
  reset_color
}

pass() {
  color "32"
  printf '%s' "PASS"
  reset_color
}

fail() {
  color "31"
  printf '%s' "FAIL"
  reset_color
}

indent() {
  sed 's/^/  /'
}

emit_event() {
  if [[ "${MODE}" != "manifest" && "${TUI_PROTOCOL}" != "1" ]]; then
    return 0
  fi

  local kind="$1"
  shift

  printf 'KFS_EVENT|%s' "${kind}"
  while [[ "$#" -gt 0 ]]; do
    printf '|%s' "$1"
    shift
  done
  printf '\n'
}

collect_section_entries() {
  local title="$1"
  local dir="$2"
  local entries="$3"
  local path
  local subgroup
  local test_case
  local description

  [[ -d "${dir}" ]] || die "missing test directory: ${dir}"

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    subgroup="$(dirname "${path}")"
    subgroup="${subgroup#${dir}}"
    subgroup="${subgroup#/}"
    [[ -n "${subgroup}" ]] || subgroup="-"
    while IFS= read -r test_case; do
      [[ -n "${test_case}" ]] || continue

      description="$(bash "${path}" --description "${test_case}")"
      [[ -n "${description}" ]] || die "missing description in ${path} for case ${test_case}"
      printf '%s\t%s\t%s\t%s\t%s\n' "${title}" "${subgroup}" "${path}" "${test_case}" "${description}" >>"${entries}"
    done < <(bash "${path}" --list)
  done < <(find "${dir}" -type f -name '*.sh' | sort)
}

format_subsection_title() {
  local subsection="$1"

  [[ "${subsection}" != "-" ]] || return 1

  subsection="${subsection//\// / }"
  subsection="${subsection//-/ }"
  subsection="${subsection//_/ }"
  printf '%s\n' "${subsection^^}"
}

build_manifest() {
  local entries="$1"

  : >"${entries}"
  printf '%s\t%s\t%s\t%s\t%s\n' "SETUP" "-" "-" "-" "Rebuild the container toolchain image" >>"${entries}"
  printf '%s\t%s\t%s\t%s\t%s\n' "SETUP" "-" "-" "-" "Verify tools exist" >>"${entries}"
  collect_section_entries "TESTS" "${SCRIPT_ROOT}/tests" "${entries}"
  collect_section_entries "STABILITY TESTS" "${SCRIPT_ROOT}/stability-tests" "${entries}"
  collect_section_entries "REJECTION TESTS" "${SCRIPT_ROOT}/rejection-tests" "${entries}"
  collect_section_entries "BOOT TESTS" "${SCRIPT_ROOT}/boot-tests" "${entries}"
}

emit_manifest() {
  local entries="$1"
  local total
  local section
  local count
  local current_section
  local subgroup
  local path
  local test_case
  local description

  total="$(wc -l <"${entries}")"
  emit_event "suite" "${ARCH}" "${total}"

  for section in "SETUP" "TESTS" "STABILITY TESTS" "REJECTION TESTS" "BOOT TESTS"; do
    count="$(awk -F'\t' -v section="${section}" '$1 == section { count += 1 } END { print count + 0 }' "${entries}")"
    emit_event "section_total" "${section}" "${count}"
  done

  while IFS=$'\t' read -r current_section subgroup path test_case description; do
    emit_event "declare" "${current_section}" "${subgroup}" "${description}"
  done <"${entries}"
}

run_item() {
  local section="$1"
  local subgroup="$2"
  local title="$3"
  shift 3

  emit_event "start" "${section}" "${subgroup}" "${title}"

  color "1;34"
  printf '%s ' "${title}"
  reset_color

  local log
  log="$(mktemp -t kfs-test.XXXXXX)"
  set +e
  "$@" >"${log}" 2>&1
  local rc="$?"
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    pass
    printf '\n'
    emit_event "result" "${section}" "${subgroup}" "${title}" "pass"
    if [[ "${VERBOSE}" == "1" ]]; then
      cat "${log}" | indent
    fi
    rm -f "${log}"
    return 0
  fi

  fail
  printf '\n'
  emit_event "result" "${section}" "${subgroup}" "${title}" "fail"
  cat "${log}" | indent
  rm -f "${log}"
  return "${rc}"
}

run_section() {
  local title="$1"
  local entries="$2"
  local printed=0
  local section
  local subgroup
  local current_subgroup="-"
  local subsection_title
  local path
  local test_case
  local description

  if ! awk -F'\t' -v title="${title}" '$1 == title { found = 1 } END { exit(found ? 0 : 1) }' "${entries}"; then
    return 0
  fi

  if [[ "${printed}" -eq 0 ]]; then
    printf '\n'
    color "1;34"; printf '%s\n' "${title}"; reset_color
    printed=1
    emit_event "section" "${title}"
  fi

  while IFS=$'\t' read -r section subgroup path test_case description; do
    [[ "${section}" == "${title}" ]] || continue
    if [[ "${subgroup}" != "${current_subgroup}" ]]; then
      current_subgroup="${subgroup}"
      if subsection_title="$(format_subsection_title "${subgroup}")"; then
        color "2"
        printf '%s\n' "${subsection_title}"
        reset_color
      fi
    fi
    if ! run_item "${title}" "${subgroup}" "${description}" bash "${path}" "${ARCH}" "${test_case}"; then
      emit_event "summary" "fail"
      exit 1
    fi
  done <"${entries}"
}

[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

export KFS_CONTAINER_TTY=0
is_tty && export KFS_CONTAINER_TTY=1

entries="$(mktemp -t kfs-manifest.XXXXXX)"
trap 'rm -f "${entries}"' EXIT
build_manifest "${entries}"

if [[ "${MODE}" == "manifest" ]]; then
  emit_manifest "${entries}"
  exit 0
fi

banner "KFS TESTS"
info "arch: ${ARCH}"
printf '\n'
if [[ "${SKIP_TUI_MANIFEST}" != "1" ]]; then
  emit_manifest "${entries}"
fi

color "1;34"; printf '%s\n' "SETUP"; reset_color
emit_event "section" "SETUP"
if ! run_item "SETUP" "-" "Rebuild the container toolchain image" \
  env KFS_FORCE_IMAGE_BUILD=1 bash scripts/container.sh build-image; then
  emit_event "summary" "fail"
  exit 1
fi

if ! run_item "SETUP" "-" "Verify tools exist" \
  bash scripts/container.sh env-check; then
  emit_event "summary" "fail"
  exit 1
fi

run_section "TESTS" "${entries}"
run_section "STABILITY TESTS" "${entries}"
run_section "REJECTION TESTS" "${entries}"
run_section "BOOT TESTS" "${entries}"

printf '\n'
pass
printf ' %s\n' "SUMMARY PASS"
emit_event "summary" "pass"
