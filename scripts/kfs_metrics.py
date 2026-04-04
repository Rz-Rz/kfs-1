from __future__ import annotations

import json
import socket
import statistics
import subprocess
import tempfile
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

PROTECTED_BRANCH = "main"
RUNS_ROOT = Path("metrics") / "runs"
DEBUG_ROOT = Path("metrics") / "debug"
SPARKLINE_BLOCKS = "▁▂▃▄▅▆▇█"


@dataclass
class RunCase:
    section: str
    subgroup: str
    name: str
    status: str


@dataclass
class GitContext:
    branch: str
    head_sha: str
    head_commit_at: str
    protected_branch: str
    protected_sha: Optional[str]
    merge_base_sha: Optional[str]
    first_unique_commit_sha: Optional[str]
    first_unique_commit_at: Optional[str]
    dirty_worktree: bool


@dataclass
class RunRecord:
    started_at: str
    finished_at: str
    duration_ms: int
    arch: str
    make_target: str
    exit_code: int
    suite_total: int
    passed: int
    failed: int
    section_totals: dict[str, int]
    section_passed: dict[str, int]
    section_failed: dict[str, int]
    cases: list[RunCase]
    git: GitContext
    debug_dir: Optional[str] = None
    raw_log_path: Optional[str] = None
    schema_version: int = 1
    run_id: str = ""


@dataclass
class MetricCard:
    key: str
    label: str
    value: str
    baseline: str
    delta: str
    sparkline: str
    tone: str
    tier: str
    gauge: str
    detail: str
    explain: str


@dataclass
class DashboardSnapshot:
    scope_branch: str
    scope_state: str
    baseline_label: str
    assumption: str
    cards: list[MetricCard]


def repo_root_for(path: str | Path) -> Path:
    return Path(path).resolve().parent.parent


def runs_root(repo_root: str | Path) -> Path:
    return Path(repo_root) / RUNS_ROOT


def default_db_path(repo_root: str | Path) -> Path:
    return runs_root(repo_root)


def debug_root(repo_root: str | Path) -> Path:
    return Path(repo_root) / DEBUG_ROOT


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def build_run_id(when: datetime, arch: str, head_sha: str) -> str:
    stamp = when.strftime("%Y-%m-%dT%H-%M-%SZ")
    host = socket.gethostname().split(".")[0] or "host"
    short_sha = (head_sha or "unknown")[:7]
    return f"{stamp}_{short_sha}_{host}_{arch}"


def capture_git_context(
    repo_root: str | Path, protected_branch: str = PROTECTED_BRANCH
) -> GitContext:
    root = Path(repo_root)
    branch = _git(root, ["rev-parse", "--abbrev-ref", "HEAD"]) or "HEAD"
    head_sha = _git(root, ["rev-parse", "HEAD"]) or "UNKNOWN"
    head_commit_at = _git(root, ["show", "-s", "--format=%cI", "HEAD"]) or utc_now().isoformat()
    protected_sha = _git(root, ["rev-parse", "--verify", protected_branch])
    merge_base_sha = None
    first_unique_commit_sha = None
    first_unique_commit_at = None

    if protected_sha:
        merge_base_sha = _git(root, ["merge-base", "HEAD", protected_branch])
        first_unique_commit_sha = _first_line(
            _git(root, ["rev-list", "--reverse", f"{protected_branch}..HEAD"])
        )
        if first_unique_commit_sha:
            first_unique_commit_at = _git(
                root, ["show", "-s", "--format=%cI", first_unique_commit_sha]
            )

    dirty_worktree = bool(_git(root, ["status", "--porcelain"]))
    return GitContext(
        branch=branch,
        head_sha=head_sha,
        head_commit_at=head_commit_at,
        protected_branch=protected_branch,
        protected_sha=protected_sha,
        merge_base_sha=merge_base_sha,
        first_unique_commit_sha=first_unique_commit_sha,
        first_unique_commit_at=first_unique_commit_at,
        dirty_worktree=dirty_worktree,
    )


def save_run(repo_root: str | Path, run: RunRecord) -> Path:
    root = Path(repo_root)
    store = runs_root(root)
    finished_at = _parse_dt(run.finished_at)
    day_dir = (
        store / finished_at.strftime("%Y") / finished_at.strftime("%m") / finished_at.strftime("%d")
    )
    day_dir.mkdir(parents=True, exist_ok=True)

    if not run.run_id:
        run.run_id = build_run_id(finished_at, run.arch, run.git.head_sha)

    path = day_dir / f"{run.run_id}.json"
    payload = asdict(run)
    payload["cases"] = [asdict(case) for case in run.cases]
    payload["git"] = asdict(run.git)
    serialized = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    with tempfile.NamedTemporaryFile("w", dir=day_dir, delete=False, encoding="utf-8") as handle:
        handle.write(serialized)
        tmp_path = Path(handle.name)
    tmp_path.replace(path)
    return path


def sync_branch_lifecycle(
    repo_root: str | Path,
    protected_branch: str = PROTECTED_BRANCH,
    fetch_remote: bool = True,
) -> None:
    root = Path(repo_root)
    _maybe_fetch_origin(root, fetch_remote)
    _ = _branch_states(load_runs(root), root, protected_branch)


def load_dashboard(
    _store_path: str | Path, repo_root: str | Path, current_branch: str
) -> DashboardSnapshot:
    root = Path(repo_root)
    records = load_runs(root)
    branch_states = _branch_states(records, root, PROTECTED_BRANCH)

    scope_state = branch_states.get(current_branch, "active")
    scope_branch = current_branch

    if current_branch == PROTECTED_BRANCH:
        baseline_label = "vs previous 30d on main"
        comparison_scope = ("window", None)
    elif any(record.git.branch != current_branch for record in records):
        baseline_label = "vs all-branch average"
        comparison_scope = ("all-other-branches", current_branch)
    else:
        baseline_label = "vs branch history"
        comparison_scope = ("branch-history", current_branch)

    assumption = ""

    branch_df = _deployment_frequency_points(records, scope_branch)
    branch_lt = _lead_time_points(records, scope_branch)
    branch_cfr = _change_failure_rate_points(records, scope_branch)
    branch_mttr = _mttr_points(records, scope_branch)

    if comparison_scope[0] == "window":
        baseline_df = _previous_window_average(branch_df)
        baseline_lt = _previous_window_average(branch_lt)
        baseline_cfr = _previous_window_average(branch_cfr)
        baseline_mttr = _previous_window_average(branch_mttr)
    elif comparison_scope[0] == "all-other-branches":
        excluded_branch = comparison_scope[1]
        baseline_df = _current_window_average(
            _deployment_frequency_points(records, None, excluded_branch)
        )
        baseline_lt = _current_window_average(_lead_time_points(records, None, excluded_branch))
        baseline_cfr = _current_window_average(
            _change_failure_rate_points(records, None, excluded_branch)
        )
        baseline_mttr = _current_window_average(_mttr_points(records, None, excluded_branch))

        baseline_df = _fallback_baseline(baseline_df, branch_df)
        baseline_lt = _fallback_baseline(baseline_lt, branch_lt)
        baseline_cfr = _fallback_baseline(baseline_cfr, branch_cfr)
        baseline_mttr = _fallback_baseline(baseline_mttr, branch_mttr)
    else:
        baseline_df = _fallback_baseline(None, branch_df)
        baseline_lt = _fallback_baseline(None, branch_lt)
        baseline_cfr = _fallback_baseline(None, branch_cfr)
        baseline_mttr = _fallback_baseline(None, branch_mttr)

    current_df = _current_window_average(branch_df)
    current_lt = _current_window_average(branch_lt)
    current_cfr = _current_window_average(branch_cfr)
    current_mttr = _current_window_average(branch_mttr)

    return DashboardSnapshot(
        scope_branch=scope_branch,
        scope_state=scope_state,
        baseline_label=baseline_label,
        assumption=assumption,
        cards=[
            _build_card(
                key="DF",
                label="Deploy Freq",
                current=current_df,
                baseline=baseline_df,
                unit_formatter=lambda value: f"{value:.1f}/wk",
                tone_func=_tone_frequency,
                higher_is_better=True,
                sparkline=_sparkline(_recent_values(branch_df, 8)),
                detail="higher is better",
            ),
            _build_card(
                key="LT",
                label="Lead Time",
                current=current_lt,
                baseline=baseline_lt,
                unit_formatter=_format_duration_hours,
                tone_func=_tone_duration,
                higher_is_better=False,
                sparkline=_sparkline(_recent_values(branch_lt, 8)),
                detail="lower is better",
            ),
            _build_card(
                key="CFR",
                label="Change Fail",
                current=current_cfr,
                baseline=baseline_cfr,
                unit_formatter=lambda value: f"{value:.1f}%",
                tone_func=_tone_failure_rate,
                higher_is_better=False,
                sparkline=_sparkline(_recent_values(branch_cfr, 8)),
                detail="lower is better",
            ),
            _build_card(
                key="MTTR",
                label="MTTR",
                current=current_mttr,
                baseline=baseline_mttr,
                unit_formatter=_format_duration_hours,
                tone_func=_tone_duration,
                higher_is_better=False,
                sparkline=_sparkline(_recent_values(branch_mttr, 8)),
                detail="lower is better",
            ),
        ],
    )


def load_runs(repo_root: str | Path) -> list[RunRecord]:
    repo_root = Path(repo_root)
    records: list[RunRecord] = []
    seen_run_ids: set[str] = set()

    for path in sorted(runs_root(repo_root).rglob("*.json")):
        if path.name.startswith("."):
            continue
        record = _load_run_record(path.read_text(encoding="utf-8"), path.stem)
        if record is None:
            continue
        if record.run_id in seen_run_ids:
            continue
        seen_run_ids.add(record.run_id)
        records.append(record)

    for record in _load_runs_from_git_refs(repo_root):
        if record.run_id in seen_run_ids:
            continue
        seen_run_ids.add(record.run_id)
        records.append(record)

    records.sort(key=lambda record: record.finished_at)
    return records


def _load_runs_from_git_refs(repo_root: Path) -> list[RunRecord]:
    records: list[RunRecord] = []
    seen_paths: set[str] = set()
    refs_output = _git(
        repo_root,
        ["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes/origin"],
    )
    if not refs_output:
        return records

    for ref in refs_output.splitlines():
        ref = ref.strip()
        if not ref:
            continue
        tree_output = _git(repo_root, ["ls-tree", "-r", "--name-only", ref, "--", str(RUNS_ROOT)])
        if not tree_output:
            continue
        for relpath in tree_output.splitlines():
            relpath = relpath.strip()
            if not relpath or relpath.endswith(".gitkeep") or not relpath.endswith(".json"):
                continue
            if relpath in seen_paths:
                continue
            seen_paths.add(relpath)
            blob = _git(repo_root, ["show", f"{ref}:{relpath}"])
            if not blob:
                continue
            record = _load_run_record(blob, Path(relpath).stem)
            if record is None:
                continue
            records.append(record)
    return records


def _load_run_record(raw_payload: str, default_run_id: str) -> Optional[RunRecord]:
    try:
        return _record_from_payload(json.loads(raw_payload), default_run_id)
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        return None


def _record_from_payload(payload: dict, default_run_id: str) -> RunRecord:
    git_payload = payload.get("git", {})
    cases_payload = payload.get("cases", [])
    return RunRecord(
        schema_version=payload.get("schema_version", 1),
        run_id=payload.get("run_id", default_run_id),
        started_at=payload["started_at"],
        finished_at=payload["finished_at"],
        duration_ms=payload["duration_ms"],
        arch=payload["arch"],
        make_target=payload["make_target"],
        exit_code=payload["exit_code"],
        suite_total=payload["suite_total"],
        passed=payload["passed"],
        failed=payload["failed"],
        section_totals=payload.get("section_totals", {}),
        section_passed=payload.get("section_passed", {}),
        section_failed=payload.get("section_failed", {}),
        cases=[RunCase(**case) for case in cases_payload],
        git=GitContext(**git_payload),
        debug_dir=payload.get("debug_dir"),
        raw_log_path=payload.get("raw_log_path"),
    )


def _branch_states(
    records: list[RunRecord], repo_root: Path, protected_branch: str
) -> dict[str, str]:
    local_branches = _list_refs(repo_root, "refs/heads", "refname:short")
    remote_branches = _list_refs(repo_root, "refs/remotes/origin", "refname:lstrip=3")
    remote_branches.pop("HEAD", None)
    protected_sha = _git(repo_root, ["rev-parse", "--verify", protected_branch])

    latest_by_branch: dict[str, RunRecord] = {}
    for record in records:
        latest_by_branch[record.git.branch] = record

    states: dict[str, str] = {}
    for branch, record in latest_by_branch.items():
        tracked_sha = (
            local_branches.get(branch) or remote_branches.get(branch) or record.git.head_sha
        )
        if branch == protected_branch:
            states[branch] = "protected"
        elif tracked_sha and protected_sha and _is_ancestor(repo_root, tracked_sha, protected_sha):
            states[branch] = "merged"
        elif branch in local_branches or branch in remote_branches:
            states[branch] = "active"
        else:
            states[branch] = "orphaned"
    return states


def _build_card(
    key: str,
    label: str,
    current: Optional[float],
    baseline: Optional[float],
    unit_formatter,
    tone_func,
    higher_is_better: bool,
    sparkline: str,
    detail: str,
) -> MetricCard:
    tier, gauge, explain = _metric_visuals(key, current)
    return MetricCard(
        key=key,
        label=label,
        value=_display_metric_value(key, current, unit_formatter),
        baseline=_display_metric_value(key, baseline, unit_formatter),
        delta=_format_delta(current, baseline, higher_is_better, unit_formatter),
        sparkline=sparkline,
        tone=tone_func(current),
        tier=tier,
        gauge=gauge,
        detail=detail,
        explain=explain,
    )


def _deployment_frequency_points(
    records: list[RunRecord],
    branch: Optional[str],
    excluded_branch: Optional[str] = None,
) -> list[tuple[datetime, float]]:
    values = [
        _parse_dt(record.finished_at)
        for record in records
        if record.exit_code == 0 and _branch_match(record.git.branch, branch, excluded_branch)
    ]
    return _weekly_counts(values)


def _lead_time_points(
    records: list[RunRecord],
    branch: Optional[str],
    excluded_branch: Optional[str] = None,
) -> list[tuple[datetime, float]]:
    rows = [
        record
        for record in records
        if record.exit_code == 0 and _branch_match(record.git.branch, branch, excluded_branch)
    ]
    if not rows:
        return []

    points: list[tuple[datetime, float]] = []
    previous_sha: Optional[str] = None
    for record in rows:
        finished_at = _parse_dt(record.finished_at)
        earliest_commit = _lead_time_commit_at(
            previous_sha=previous_sha,
            current_sha=record.git.head_sha,
            fallback_first_unique=record.git.first_unique_commit_at,
            fallback_head_commit=record.git.head_commit_at,
        )
        if earliest_commit is not None:
            points.append(
                (finished_at, max((finished_at - earliest_commit).total_seconds() / 3600.0, 0.0))
            )
        previous_sha = record.git.head_sha
    return points


def _change_failure_rate_points(
    records: list[RunRecord],
    branch: Optional[str],
    excluded_branch: Optional[str] = None,
) -> list[tuple[datetime, float]]:
    samples = [
        (_parse_dt(record.finished_at), 1.0 if record.exit_code != 0 else 0.0)
        for record in records
        if _branch_match(record.git.branch, branch, excluded_branch)
    ]
    return _weekly_ratios(samples)


def _mttr_points(
    records: list[RunRecord],
    branch: Optional[str],
    excluded_branch: Optional[str] = None,
) -> list[tuple[datetime, float]]:
    rows = [
        record for record in records if _branch_match(record.git.branch, branch, excluded_branch)
    ]
    if rows and not any(record.exit_code != 0 for record in rows):
        return [(_parse_dt(record.finished_at), 0.0) for record in rows]

    incident_start: Optional[datetime] = None
    points: list[tuple[datetime, float]] = []
    for record in rows:
        finished_at = _parse_dt(record.finished_at)
        if record.exit_code != 0:
            if incident_start is None:
                incident_start = finished_at
            continue
        if incident_start is not None:
            points.append(
                (finished_at, max((finished_at - incident_start).total_seconds() / 3600.0, 0.0))
            )
            incident_start = None
    return points


def _lead_time_commit_at(
    previous_sha: Optional[str],
    current_sha: str,
    fallback_first_unique: Optional[str],
    fallback_head_commit: Optional[str],
) -> Optional[datetime]:
    if previous_sha and previous_sha != current_sha and fallback_head_commit:
        return _parse_dt(fallback_head_commit)
    if fallback_first_unique:
        return _parse_dt(fallback_first_unique)
    if fallback_head_commit:
        return _parse_dt(fallback_head_commit)
    return None


def _branch_match(branch_name: str, branch: Optional[str], excluded_branch: Optional[str]) -> bool:
    if branch is None:
        return branch_name != excluded_branch
    return branch_name == branch


def _weekly_counts(datetimes: list[datetime]) -> list[tuple[datetime, float]]:
    if not datetimes:
        return []
    end = utc_now()
    window_start = _floor_week(min(datetimes))
    points: list[tuple[datetime, float]] = []
    while window_start <= end:
        window_end = window_start + timedelta(days=7)
        count = sum(1 for item in datetimes if window_start <= item < window_end)
        points.append((min(window_end, end), float(count)))
        window_start = window_end
    return points


def _weekly_ratios(samples: list[tuple[datetime, float]]) -> list[tuple[datetime, float]]:
    if not samples:
        return []
    end = utc_now()
    window_start = _floor_week(samples[0][0])
    points: list[tuple[datetime, float]] = []
    while window_start <= end:
        window_end = window_start + timedelta(days=7)
        window = [value for when, value in samples if window_start <= when < window_end]
        if window:
            points.append((min(window_end, end), (sum(window) / len(window)) * 100.0))
        window_start = window_end
    return points


def _current_window_average(
    points: list[tuple[datetime, float]], days: int = 30
) -> Optional[float]:
    now = utc_now()
    cutoff = now - timedelta(days=days)
    values = [value for when, value in points if cutoff <= when <= now]
    return statistics.fmean(values) if values else None


def _previous_window_average(
    points: list[tuple[datetime, float]], days: int = 30
) -> Optional[float]:
    now = utc_now()
    prev_end = now - timedelta(days=days)
    prev_start = now - timedelta(days=days * 2)
    values = [value for when, value in points if prev_start <= when < prev_end]
    return statistics.fmean(values) if values else None


def _all_time_average_excluding_latest(points: list[tuple[datetime, float]]) -> Optional[float]:
    if len(points) <= 1:
        return None
    return statistics.fmean([value for _when, value in points[:-1]])


def _fallback_baseline(
    primary: Optional[float], branch_points: list[tuple[datetime, float]]
) -> Optional[float]:
    if primary is not None:
        return primary
    previous_window = _previous_window_average(branch_points)
    if previous_window is not None:
        return previous_window
    historical = _all_time_average_excluding_latest(branch_points)
    if historical is not None:
        return historical
    return _current_window_average(branch_points)


def _tone_frequency(value: Optional[float]) -> str:
    if value is None:
        return "idle"
    if value >= 1.0:
        return "good"
    if value >= 0.25:
        return "warn"
    return "bad"


def _tone_duration(value: Optional[float]) -> str:
    if value is None:
        return "idle"
    if value <= 24.0:
        return "good"
    if value <= 168.0:
        return "warn"
    return "bad"


def _tone_failure_rate(value: Optional[float]) -> str:
    if value is None:
        return "idle"
    if value <= 15.0:
        return "good"
    if value <= 30.0:
        return "warn"
    return "bad"


def _display_metric_value(key: str, value: Optional[float], formatter) -> str:
    if value is None:
        return "--"
    if key in {"CFR", "MTTR"} and abs(value) < 1e-9:
        return "CLEAN"
    return formatter(value)


def _format_delta(
    current: Optional[float],
    baseline: Optional[float],
    higher_is_better: bool,
    formatter,
) -> str:
    if current is None or baseline is None:
        return "n/a"
    delta = current - baseline
    if abs(delta) < 1e-9:
        return "flat"
    improved = delta > 0 if higher_is_better else delta < 0
    arrow = "↑" if improved else "↓"
    return f"{arrow} {formatter(abs(delta))}"


def _metric_visuals(key: str, value: Optional[float]) -> tuple[str, str, str]:
    if key == "DF":
        return _visual_from_thresholds(
            value,
            (0.25, 1.0, 7.0),
            ("LOW", "MED", "HIGH", "ELITE"),
            True,
            14.0,
            "Deployment frequency tiers: <0.25/wk low, >=0.25 med, >=1 high, >=7 elite",
        )
    if key == "LT":
        return _visual_from_thresholds(
            value,
            (720.0, 168.0, 24.0),
            ("LOW", "MED", "HIGH", "ELITE"),
            False,
            1440.0,
            "Lead time tiers: >30d low, <=30d med, <=7d high, <=1d elite",
        )
    if key == "CFR":
        return _visual_from_thresholds(
            value,
            (45.0, 30.0, 15.0),
            ("LOW", "MED", "HIGH", "ELITE"),
            False,
            100.0,
            "Change failure rate tiers: >45% low, <=45% med, <=30% high, <=15% elite",
        )
    if key == "MTTR":
        return _visual_from_thresholds(
            value,
            (168.0, 24.0, 1.0),
            ("LOW", "MED", "HIGH", "ELITE"),
            False,
            336.0,
            "MTTR tiers: >7d low, <=7d med, <=24h high, <=1h elite",
        )
    return ("NO DATA", "░░░░░░░░░░░░", "No thresholds available")


def _visual_from_thresholds(
    value: Optional[float],
    bands: tuple[float, float, float],
    band_labels: tuple[str, str, str, str],
    higher_is_better: bool,
    cap: float,
    explain: str,
) -> tuple[str, str, str]:
    if value is None:
        return ("NO DATA", "░░░░░░░░░░░░", explain)
    total_slots = 12
    if higher_is_better:
        first, second, third = bands
        if value < first:
            tier_index = 0
        elif value < second:
            tier_index = 1
        elif value < third:
            tier_index = 2
        else:
            tier_index = 3
        normalized = min(max(value / max(cap, 1e-9), 0.0), 1.0)
    else:
        first, second, third = bands
        if value > first:
            tier_index = 0
        elif value > second:
            tier_index = 1
        elif value > third:
            tier_index = 2
        else:
            tier_index = 3
        normalized = 1.0 - min(max(value / max(cap, 1e-9), 0.0), 1.0)
    marker_index = min(total_slots - 1, max(0, int(round(normalized * (total_slots - 1)))))
    lane = ["·"] * total_slots
    lane[marker_index] = "◆"
    return (band_labels[tier_index], "".join(lane), explain)


def _recent_values(points: list[tuple[datetime, float]], count: int) -> list[Optional[float]]:
    return [value for _when, value in points[-count:]]


def _sparkline(values: list[Optional[float]]) -> str:
    if not values:
        return "........"
    numeric = [value for value in values if value is not None]
    if not numeric:
        return "." * len(values)
    low = min(numeric)
    high = max(numeric)
    span = max(high - low, 1e-9)
    result: list[str] = []
    for value in values:
        if value is None:
            result.append(".")
            continue
        index = int(round(((value - low) / span) * (len(SPARKLINE_BLOCKS) - 1)))
        result.append(SPARKLINE_BLOCKS[max(0, min(index, len(SPARKLINE_BLOCKS) - 1))])
    return "".join(result)


def _format_duration_hours(value: Optional[float]) -> str:
    if value is None:
        return "--"
    if value < 48.0:
        return f"{value:.1f}h"
    return f"{value / 24.0:.1f}d"


def _floor_week(value: datetime) -> datetime:
    weekday = value.weekday()
    floored = value - timedelta(days=weekday)
    return floored.replace(hour=0, minute=0, second=0, microsecond=0)


def _maybe_fetch_origin(repo_root: Path, fetch_remote: bool) -> None:
    if not fetch_remote:
        return
    if _git(repo_root, ["remote", "get-url", "origin"]) is None:
        return
    subprocess.run(
        ["git", "fetch", "--prune", "--quiet", "origin"],
        cwd=repo_root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def _list_refs(repo_root: Path, ref_prefix: str, format_field: str) -> dict[str, str]:
    output = _git(
        repo_root, ["for-each-ref", "--format", f"%({format_field})\t%(objectname)", ref_prefix]
    )
    refs: dict[str, str] = {}
    if not output:
        return refs
    for line in output.splitlines():
        name, _, sha = line.partition("\t")
        if name and sha:
            refs[name] = sha
    return refs


def _is_ancestor(repo_root: Path, ancestor: str, descendant: str) -> bool:
    process = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=repo_root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return process.returncode == 0


def _git(repo_root: Path, args: list[str]) -> Optional[str]:
    process = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if process.returncode != 0:
        return None
    return process.stdout.strip()


def _first_line(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    return value.splitlines()[0].strip() or None


def _parse_dt(value: Optional[str]) -> datetime:
    if not value:
        return utc_now()
    return datetime.fromisoformat(value)
