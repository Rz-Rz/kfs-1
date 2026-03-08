#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from kfs_metrics import (
    RunCase,
    RunRecord,
    capture_git_context,
    repo_root_for,
    save_run,
    sync_branch_lifecycle,
)


EVENT_PREFIX = "KFS_EVENT|"


@dataclass
class CaseState:
    section: str
    subgroup: str
    name: str
    status: str = "wait"


class ProtocolCapture:
    def __init__(self) -> None:
        self.suite_total = 0
        self.section_totals: dict[str, int] = {}
        self.section_passed: dict[str, int] = {}
        self.section_failed: dict[str, int] = {}
        self.cases: dict[tuple[str, str, str], CaseState] = {}

    def process_line(self, line: str) -> None:
        if not line.startswith(EVENT_PREFIX):
            return
        parts = line.split("|")
        kind = parts[1] if len(parts) > 1 else ""

        if kind == "suite" and len(parts) >= 4:
            self.suite_total = int(parts[3])
            return
        if kind == "suite_total" and len(parts) >= 3:
            self.suite_total = int(parts[2])
            return
        if kind == "section_total" and len(parts) >= 4:
            self.section_totals[parts[2]] = int(parts[3])
            return
        if kind == "declare" and len(parts) >= 4:
            section, subgroup, name = self._event_item(parts)
            self.cases.setdefault((section, subgroup, name), CaseState(section, subgroup, name))
            return
        if kind == "result" and len(parts) >= 5:
            section, subgroup, name = self._event_item(parts)
            status = parts[5] if len(parts) >= 6 else parts[4]
            key = (section, subgroup, name)
            case = self.cases.setdefault(key, CaseState(section, subgroup, name))
            case.status = status
            if status == "pass":
                self.section_passed[section] = self.section_passed.get(section, 0) + 1
            elif status == "fail":
                self.section_failed[section] = self.section_failed.get(section, 0) + 1

    def to_cases(self) -> list[RunCase]:
        return [
            RunCase(
                section=case.section,
                subgroup=case.subgroup,
                name=case.name,
                status=case.status,
            )
            for case in self.cases.values()
        ]

    @staticmethod
    def _event_item(parts: list[str]) -> tuple[str, str, str]:
        if len(parts) >= 5:
            return parts[2], parts[3], parts[4]
        return parts[2], "-", parts[3]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run KFS tests and persist history")
    parser.add_argument("--arch", default="i386")
    parser.add_argument("--make-target", default="test-plain")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = repo_root_for(__file__)
    started_at = datetime.now(timezone.utc)
    capture = ProtocolCapture()

    process = subprocess.Popen(
        ["bash", "scripts/test-host.sh", args.arch],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env={
            **os.environ.copy(),
            "KFS_TUI_PROTOCOL": "1",
        },
    )

    assert process.stdout is not None
    for raw_line in process.stdout:
        sys.stdout.write(raw_line)
        sys.stdout.flush()
        capture.process_line(raw_line.rstrip("\n"))

    exit_code = process.wait()
    finished_at = datetime.now(timezone.utc)

    try:
        git = capture_git_context(repo_root)
        run = RunRecord(
            started_at=started_at.isoformat(),
            finished_at=finished_at.isoformat(),
            duration_ms=int((finished_at - started_at).total_seconds() * 1000),
            arch=args.arch,
            make_target=args.make_target,
            exit_code=exit_code,
            suite_total=capture.suite_total or len(capture.cases),
            passed=sum(1 for case in capture.cases.values() if case.status == "pass"),
            failed=sum(1 for case in capture.cases.values() if case.status == "fail"),
            section_totals=capture.section_totals,
            section_passed=capture.section_passed,
            section_failed=capture.section_failed,
            cases=capture.to_cases(),
            git=git,
        )
        save_run(repo_root, run)
        sync_branch_lifecycle(repo_root, fetch_remote=True)
    except Exception as exc:
        print(f"warn: failed to persist KFS test metrics: {exc}", file=sys.stderr)

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
