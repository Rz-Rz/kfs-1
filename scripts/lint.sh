#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNNER="${ROOT_DIR}/scripts/lint-runner.sh"
REQUIRED_TOOLS=(
	bash
	python3
	rg
	rustfmt
	rustc
	shellcheck
	shfmt
	black
	ruff
)

have_all_tools() {
	local tool

	for tool in "${REQUIRED_TOOLS[@]}"; do
		if ! command -v "${tool}" >/dev/null 2>&1; then
			return 1
		fi
	done

	return 0
}

run_direct() {
	exec bash "${RUNNER}"
}

run_in_container() {
	exec make --no-print-directory -C "${ROOT_DIR}" lint
}

if [[ "${KFS_HOST_TEST_DIRECT:-0}" == "1" ]]; then
	run_direct
fi

if have_all_tools; then
	run_direct
fi

run_in_container
