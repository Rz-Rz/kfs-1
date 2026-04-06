#!/usr/bin/env bash
set -euo pipefail

MODE="run"
ARCH="${1:-i386}"
SUITE_LOCKED="${KFS_TEST_SUITE_LOCKED:-0}"
VERBOSE="${KFS_VERBOSE:-0}"
TUI_PROTOCOL="${KFS_TUI_PROTOCOL:-0}"
SKIP_TUI_MANIFEST="${KFS_TUI_SKIP_MANIFEST:-0}"
DEBUG_DIR="${KFS_TEST_DEBUG_DIR:-}"
RUN_LINT="${KFS_RUN_LINT:-0}"
PARALLEL_JOBS="${KFS_TEST_JOBS:-auto}"
SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_ROOT}/.." && pwd)"
DEBUG_INDEX=""
ENTRIES_FILE=""
TEST_FAILURES=0
RUNNING_JOBS=0
ACTIVE_LOCAL_JOBS=0
ACTIVE_HEAVY_JOBS=0
WORKSPACE_POOL_ROOT=""
WORKSPACE_COUNT=0
declare -A ACTIVE_CASE_SECTION=()
declare -A ACTIVE_CASE_SUBGROUP=()
declare -A ACTIVE_CASE_TITLE=()
declare -A ACTIVE_CASE_PATH=()
declare -A ACTIVE_CASE_NAME=()
declare -A ACTIVE_CASE_LOG=()
declare -A ACTIVE_CASE_MODE=()
declare -A ACTIVE_CASE_WORKSPACE_SLOT=()
declare -A PRINTED_SECTION_HEADERS=()
declare -a WORKSPACE_DIRS=()
declare -a WORKSPACE_BUSY=()

if [[ "${ARCH}" == "--manifest" ]]; then
	MODE="manifest"
	ARCH="${2:-i386}"
fi

if [[ "${ARCH}" == "--suite-run" ]]; then
	ARCH="${2:-i386}"
	SUITE_LOCKED=1
fi

die() {
	echo "error: $*" >&2
	exit 2
}

cleanup() {
	local exit_code="${1:-$?}"

	trap - EXIT
	jobs -pr | xargs -r kill >/dev/null 2>&1 || true
	rm -f "${ENTRIES_FILE}"
	if [[ -n "${WORKSPACE_POOL_ROOT}" && "${KFS_KEEP_TEST_WORKSPACES:-0}" != "1" ]]; then
		rm -rf "${WORKSPACE_POOL_ROOT}"
	fi
	exit "${exit_code}"
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

slugify() {
	printf '%s' "$1" |
		tr '[:upper:]' '[:lower:]' |
		sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

default_parallel_jobs() {
	local jobs

	if command -v nproc >/dev/null 2>&1; then
		jobs="$(nproc)"
	else
		jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
	fi

	[[ "${jobs}" =~ ^[0-9]+$ ]] || jobs=1
	((jobs >= 1)) || jobs=1
	((jobs <= 4)) || jobs=4
	printf '%s\n' "${jobs}"
}

resolved_parallel_jobs() {
	case "${PARALLEL_JOBS}" in
	"" | auto)
		default_parallel_jobs
		;;
	*)
		[[ "${PARALLEL_JOBS}" =~ ^[0-9]+$ ]] || die "KFS_TEST_JOBS must be auto or a positive integer"
		((PARALLEL_JOBS >= 1)) || die "KFS_TEST_JOBS must be at least 1"
		printf '%s\n' "${PARALLEL_JOBS}"
		;;
	esac
}

heavy_parallel_jobs() {
	local total="$1"

	if ((total <= 1)); then
		printf '0\n'
		return 0
	fi

	printf '%s\n' $(((total + 1) / 2))
}

case_execution_mode() {
	local path="$1"

	case "${path}" in
	*/tests/unit/*)
		printf '%s\n' "local"
		;;
	*)
		printf '%s\n' "workspace"
		;;
	esac
}

relative_case_path() {
	local path="$1"

	if [[ "${path}" == "${REPO_ROOT}/"* ]]; then
		printf '%s\n' "${path#"${REPO_ROOT}/"}"
		return 0
	fi

	printf '%s\n' "${path}"
}

sync_workspace_copy() {
	local workspace="$1"

	rsync -a --delete \
		--exclude '.tmp/' \
		--exclude '.history/' \
		--exclude '.venv-test-ui/' \
		"${REPO_ROOT}/" "${workspace}/"
}

init_workspace_pool() {
	local count="$1"
	local index
	local workspace

	WORKSPACE_COUNT="${count}"
	((WORKSPACE_COUNT > 0)) || return 0

	mkdir -p "${REPO_ROOT}/.tmp"
	WORKSPACE_POOL_ROOT="$(mktemp -d "${REPO_ROOT}/.tmp/test-host-workspaces.XXXXXX")"

	for ((index = 0; index < WORKSPACE_COUNT; index += 1)); do
		workspace="${WORKSPACE_POOL_ROOT}/worker-${index}"
		mkdir -p "${workspace}"
		sync_workspace_copy "${workspace}"
		WORKSPACE_DIRS[index]="${workspace}"
		WORKSPACE_BUSY[index]=0
	done
}

find_free_workspace_slot() {
	local index

	for ((index = 0; index < WORKSPACE_COUNT; index += 1)); do
		if [[ "${WORKSPACE_BUSY[index]:-0}" -eq 0 ]]; then
			printf '%s\n' "${index}"
			return 0
		fi
	done

	return 1
}

init_debug_index() {
	[[ -n "${DEBUG_DIR}" ]] || return 0
	mkdir -p "${DEBUG_DIR}"
	DEBUG_INDEX="${DEBUG_DIR}/case-index.tsv"
	if [[ ! -f "${DEBUG_INDEX}" ]]; then
		printf 'section\tsubgroup\tcase\ttitle\trc\tlog_path\n' >"${DEBUG_INDEX}"
	fi
}

persist_case_log() {
	local section="$1"
	local subgroup="$2"
	local title="$3"
	local test_case="$4"
	local rc="$5"
	local log="$6"
	local section_slug subgroup_slug case_slug path

	[[ -n "${DEBUG_DIR}" ]] || return 0

	section_slug="$(slugify "${section}")"
	subgroup_slug="$(slugify "${subgroup}")"
	case_slug="$(slugify "${test_case}")"

	[[ -n "${section_slug}" ]] || section_slug="unknown-section"
	[[ -n "${subgroup_slug}" ]] || subgroup_slug="root"
	[[ -n "${case_slug}" && "${case_slug}" != "-" ]] || case_slug="$(slugify "${title}")"
	[[ -n "${case_slug}" ]] || case_slug="unnamed-case"

	path="${DEBUG_DIR}/${section_slug}/${subgroup_slug}/${case_slug}.log"
	mkdir -p "$(dirname "${path}")"
	cp "${log}" "${path}"

	if [[ -n "${DEBUG_INDEX}" ]]; then
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
			"${section}" \
			"${subgroup}" \
			"${test_case}" \
			"${title}" \
			"${rc}" \
			"${path}" >>"${DEBUG_INDEX}"
	fi
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
		subgroup="${subgroup#"${dir}"}"
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
	if [[ "${RUN_LINT}" == "1" ]]; then
		printf '%s\t%s\t%s\t%s\t%s\n' "LINT" "-" "-" "-" "Run lint checks" >>"${entries}"
	fi
	printf '%s\t%s\t%s\t%s\t%s\n' "SETUP" "-" "-" "-" "Rebuild the container toolchain image" >>"${entries}"
	printf '%s\t%s\t%s\t%s\t%s\n' "SETUP" "-" "-" "-" "Verify tools exist" >>"${entries}"
	printf '%s\t%s\t%s\t%s\t%s\n' "SETUP" "-" "-" "-" "Verify host test tools exist" >>"${entries}"
	printf '%s\t%s\t%s\t%s\t%s\n' "SETUP" "-" "-" "-" "Build canonical release ISO/IMG artifacts" >>"${entries}"
	printf '%s\t%s\t%s\t%s\t%s\n' "SETUP" "-" "-" "-" "Build test ISO/IMG artifacts" >>"${entries}"
	collect_section_entries "TESTS" "${SCRIPT_ROOT}/tests" "${entries}"
	if [[ -d "${SCRIPT_ROOT}/architecture-tests" ]]; then
		collect_section_entries "ARCHITECTURE TESTS" "${SCRIPT_ROOT}/architecture-tests" "${entries}"
	fi
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

	for section in "LINT" "SETUP" "TESTS" "ARCHITECTURE TESTS" "STABILITY TESTS" "REJECTION TESTS" "BOOT TESTS"; do
		count="$(awk -F'\t' -v section="${section}" '$1 == section { count += 1 } END { print count + 0 }' "${entries}")"
		emit_event "section_total" "${section}" "${count}"
	done

	while IFS=$'\t' read -r current_section subgroup path test_case description; do
		emit_event "declare" "${current_section}" "${subgroup}" "${description}" "${path}" "${test_case}"
	done <"${entries}"
}

run_item() {
	local section="$1"
	local subgroup="$2"
	local title="$3"
	local path="$4"
	local test_case="$5"
	shift 5

	emit_event "start" "${section}" "${subgroup}" "${title}" "${path}" "${test_case}"

	color "1;34"
	printf '%s ' "${title}"
	reset_color

	local log
	log="$(mktemp -t kfs-test.XXXXXX)"
	set +e
	"$@" >"${log}" 2>&1
	local rc="$?"
	set -e
	persist_case_log "${section}" "${subgroup}" "${title}" "${test_case}" "${rc}" "${log}"

	if [[ "${rc}" -eq 0 ]]; then
		pass
		printf '\n'
		emit_event "result" "${section}" "${subgroup}" "${title}" "pass" "${path}" "${test_case}"
		if [[ "${VERBOSE}" == "1" ]]; then
			indent <"${log}"
		fi
		rm -f "${log}"
		return 0
	fi

	fail
	printf '\n'
	emit_event "result" "${section}" "${subgroup}" "${title}" "fail" "${path}" "${test_case}"
	indent <"${log}"
	rm -f "${log}"
	return "${rc}"
}

print_section_header_once() {
	local section="$1"

	[[ -n "${PRINTED_SECTION_HEADERS[${section}]:-}" ]] && return 0

	printf '\n'
	color "1;34"
	printf '%s\n' "${section}"
	reset_color
	PRINTED_SECTION_HEADERS["${section}"]=1
}

dispatch_case() {
	local section="$1"
	local subgroup="$2"
	local path="$3"
	local test_case="$4"
	local description="$5"
	local mode="$6"
	local workspace_slot="${7:-}"
	local log
	local pid
	local case_rel
	local run_root

	case_rel="$(relative_case_path "${path}")"
	run_root="${REPO_ROOT}"
	if [[ "${mode}" == "workspace" ]]; then
		[[ -n "${workspace_slot}" ]] || die "missing workspace slot for ${path}"
		run_root="${WORKSPACE_DIRS[workspace_slot]}"
		WORKSPACE_BUSY[workspace_slot]=1
		ACTIVE_HEAVY_JOBS=$((ACTIVE_HEAVY_JOBS + 1))
	else
		ACTIVE_LOCAL_JOBS=$((ACTIVE_LOCAL_JOBS + 1))
	fi

	print_section_header_once "${section}"
	emit_event "section" "${section}"
	emit_event "start" "${section}" "${subgroup}" "${description}" "${path}" "${test_case}"

	log="$(mktemp -t kfs-test.XXXXXX)"
	(
		set +e
		cd "${run_root}"
		bash "${case_rel}" "${ARCH}" "${test_case}" >"${log}" 2>&1
		exit "$?"
	) &
	pid="$!"

	ACTIVE_CASE_SECTION["${pid}"]="${section}"
	ACTIVE_CASE_SUBGROUP["${pid}"]="${subgroup}"
	ACTIVE_CASE_TITLE["${pid}"]="${description}"
	ACTIVE_CASE_PATH["${pid}"]="${path}"
	ACTIVE_CASE_NAME["${pid}"]="${test_case}"
	ACTIVE_CASE_LOG["${pid}"]="${log}"
	ACTIVE_CASE_MODE["${pid}"]="${mode}"
	ACTIVE_CASE_WORKSPACE_SLOT["${pid}"]="${workspace_slot}"
	RUNNING_JOBS=$((RUNNING_JOBS + 1))
}

complete_case() {
	local pid="$1"
	local rc="$2"
	local section="${ACTIVE_CASE_SECTION[${pid}]}"
	local subgroup="${ACTIVE_CASE_SUBGROUP[${pid}]}"
	local title="${ACTIVE_CASE_TITLE[${pid}]}"
	local path="${ACTIVE_CASE_PATH[${pid}]}"
	local test_case="${ACTIVE_CASE_NAME[${pid}]}"
	local log="${ACTIVE_CASE_LOG[${pid}]}"
	local mode="${ACTIVE_CASE_MODE[${pid}]:-local}"
	local workspace_slot="${ACTIVE_CASE_WORKSPACE_SLOT[${pid}]:-}"

	unset "ACTIVE_CASE_SECTION[${pid}]"
	unset "ACTIVE_CASE_SUBGROUP[${pid}]"
	unset "ACTIVE_CASE_TITLE[${pid}]"
	unset "ACTIVE_CASE_PATH[${pid}]"
	unset "ACTIVE_CASE_NAME[${pid}]"
	unset "ACTIVE_CASE_LOG[${pid}]"
	unset "ACTIVE_CASE_MODE[${pid}]"
	unset "ACTIVE_CASE_WORKSPACE_SLOT[${pid}]"
	if [[ "${mode}" == "workspace" ]]; then
		WORKSPACE_BUSY[workspace_slot]=0
		ACTIVE_HEAVY_JOBS=$((ACTIVE_HEAVY_JOBS - 1))
	else
		ACTIVE_LOCAL_JOBS=$((ACTIVE_LOCAL_JOBS - 1))
	fi
	RUNNING_JOBS=$((RUNNING_JOBS - 1))

	persist_case_log "${section}" "${subgroup}" "${title}" "${test_case}" "${rc}" "${log}"

	color "1;34"
	printf '[%s] ' "${section}"
	reset_color
	printf '%s ' "${title}"

	if [[ "${rc}" -eq 0 ]]; then
		pass
		printf '\n'
		emit_event "result" "${section}" "${subgroup}" "${title}" "pass" "${path}" "${test_case}"
		if [[ "${VERBOSE}" == "1" ]]; then
			indent <"${log}"
		fi
	else
		fail
		printf '\n'
		emit_event "result" "${section}" "${subgroup}" "${title}" "fail" "${path}" "${test_case}"
		indent <"${log}"
		TEST_FAILURES=1
	fi

	rm -f "${log}"
}

reap_next_case() {
	local pid
	local rc

	set +e
	wait -n -p pid
	rc="$?"
	set -e
	complete_case "${pid}" "${rc}"
}

run_parallel_cases() {
	local entries="$1"
	local max_jobs="$2"
	local heavy_jobs="$3"
	local local_jobs=0
	local local_pending=()
	local heavy_pending=()
	local local_index=0
	local heavy_index=0
	local item
	local section
	local subgroup
	local path
	local test_case
	local description
	local mode
	local workspace_slot
	local scheduled

	while IFS=$'\t' read -r section subgroup path test_case description; do
		case "${section}" in
		"TESTS" | "ARCHITECTURE TESTS" | "STABILITY TESTS" | "REJECTION TESTS" | "BOOT TESTS")
			mode="$(case_execution_mode "${path}")"
			item="${section}"$'\t'"${subgroup}"$'\t'"${path}"$'\t'"${test_case}"$'\t'"${description}"
			if [[ "${mode}" == "workspace" ]]; then
				heavy_pending+=("${item}")
			else
				local_pending+=("${item}")
			fi
			;;
		*)
			continue
			;;
		esac
	done <"${entries}"

	local_jobs=$((max_jobs - heavy_jobs))

	while ((local_index < ${#local_pending[@]} || heavy_index < ${#heavy_pending[@]} || RUNNING_JOBS > 0)); do
		scheduled=0
		while ((RUNNING_JOBS < max_jobs)); do
			workspace_slot=""
			if ((heavy_index < ${#heavy_pending[@]})); then
				workspace_slot="$(find_free_workspace_slot || true)"
				if [[ -n "${workspace_slot}" ]]; then
					item="${heavy_pending[heavy_index]}"
					heavy_index=$((heavy_index + 1))
					IFS=$'\t' read -r section subgroup path test_case description <<<"${item}"
					dispatch_case "${section}" "${subgroup}" "${path}" "${test_case}" "${description}" "workspace" "${workspace_slot}"
					scheduled=1
					continue
				fi
			fi

			if ((local_index < ${#local_pending[@]})); then
				if ((local_jobs == 0 && heavy_index < ${#heavy_pending[@]})); then
					break
				fi
				item="${local_pending[local_index]}"
				local_index=$((local_index + 1))
				IFS=$'\t' read -r section subgroup path test_case description <<<"${item}"
				dispatch_case "${section}" "${subgroup}" "${path}" "${test_case}" "${description}" "local"
				scheduled=1
				continue
			fi

			break
		done

		if ((RUNNING_JOBS > 0)); then
			reap_next_case
			continue
		fi

		if ((scheduled == 0)); then
			break
		fi
	done

	return "${TEST_FAILURES}"
}

[[ "${ARCH}" == "i386" ]] || die "unsupported arch: ${ARCH}"

if [[ "${MODE}" != "manifest" && "${SUITE_LOCKED}" != "1" ]]; then
	exec env KFS_TEST_SUITE_LOCKED=1 \
		bash "${SCRIPT_ROOT}/with-test-suite-lock.sh" \
		bash "${SCRIPT_ROOT}/test-host.sh" --suite-run "${ARCH}"
fi

export KFS_CONTAINER_TTY=0

ENTRIES_FILE="$(mktemp -t kfs-manifest.XXXXXX)"
trap 'cleanup "$?"' EXIT
build_manifest "${ENTRIES_FILE}"
init_debug_index

if [[ "${MODE}" == "manifest" ]]; then
	emit_manifest "${ENTRIES_FILE}"
	exit 0
fi

banner "KFS TESTS"
info "arch: ${ARCH}"
printf '\n'
if [[ "${SKIP_TUI_MANIFEST}" != "1" ]]; then
	emit_manifest "${ENTRIES_FILE}"
fi

if [[ "${RUN_LINT}" == "1" ]]; then
	color "1;34"
	printf '%s\n' "LINT"
	reset_color
	emit_event "section" "LINT"
	if ! run_item "LINT" "-" "Run lint checks" "-" "-" \
		bash scripts/lint.sh; then
		emit_event "summary" "fail"
		exit 1
	fi
	printf '\n'
fi

color "1;34"
printf '%s\n' "SETUP"
reset_color
emit_event "section" "SETUP"
if ! run_item "SETUP" "-" "Rebuild the container toolchain image" "-" "-" \
	env KFS_FORCE_IMAGE_BUILD=1 make --no-print-directory container-image; then
	emit_event "summary" "fail"
	exit 1
fi

if ! run_item "SETUP" "-" "Verify tools exist" "-" "-" \
	make --no-print-directory container-env-check; then
	emit_event "summary" "fail"
	exit 1
fi

if ! run_item "SETUP" "-" "Verify host test tools exist" "-" "-" \
	bash -lc 'command -v rg >/dev/null 2>&1'; then
	emit_event "summary" "fail"
	exit 1
fi

if ! run_item "SETUP" "-" "Build canonical release ISO/IMG artifacts" "-" "-" \
	bash scripts/with-build-lock.sh \
	bash -lc "make -B img arch='${ARCH}' >/dev/null"; then
	emit_event "summary" "fail"
	exit 1
fi

if ! run_item "SETUP" "-" "Build test ISO/IMG artifacts" "-" "-" \
	bash scripts/with-build-lock.sh \
	bash -lc "make -B img-test arch='${ARCH}' >/dev/null"; then
	emit_event "summary" "fail"
	exit 1
fi

PARALLEL_JOBS="$(resolved_parallel_jobs)"
WORKSPACE_COUNT="$(heavy_parallel_jobs "${PARALLEL_JOBS}")"
init_workspace_pool "${WORKSPACE_COUNT}"
info "parallel jobs: ${PARALLEL_JOBS}"
if ((WORKSPACE_COUNT > 0)); then
	printf '\n'
	info "heavy workers: ${WORKSPACE_COUNT}"
fi
printf '\n'

run_parallel_cases "${ENTRIES_FILE}" "${PARALLEL_JOBS}" "${WORKSPACE_COUNT}"
TEST_FAILURES="$?"

printf '\n'
if [[ "${TEST_FAILURES}" -eq 0 ]]; then
	pass
	printf ' %s\n' "SUMMARY PASS"
	emit_event "summary" "pass"
else
	fail
	printf ' %s\n' "SUMMARY FAIL"
	emit_event "summary" "fail"
	exit 1
fi
