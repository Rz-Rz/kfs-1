#!/usr/bin/env python3
"""
KFS TUI — Retro terminal test runner

Usage:
  python3 scripts/kfs_tui.py
  python3 scripts/kfs_tui.py --arch i386
  python3 scripts/kfs_tui.py --demo
  cat test_output.txt | python3 scripts/kfs_tui.py --stdin
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from typing import Optional

from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Grid, Horizontal, Vertical, VerticalScroll
from textual.geometry import Size
from textual.widget import Widget
from textual.widgets import Static

from kfs_metrics import DashboardSnapshot, default_db_path, load_dashboard, repo_root_for

AMBER = "#FFB300"
AMBER_DIM = "#7A5500"
AMBER_FAINT = "#3A2800"
AMBER_GLOW = "#FFCC44"
ORANGE_ACTIVE = "#FFB300"
ORANGE_BASE = "#5A3200"
ORANGE_HEAD = "#FFCC44"
RED_BRIGHT = "#FF3333"
RED_DIM = "#881111"
GREEN_OK = "#44FF88"
BLACK = "#000000"
ACTIVE_CYCLE_SECS = 5.0
ACTIVE_SEGMENT_RATIO = 0.10
RUNNER_TICK_SECS = 0.05
MAX_ACTIVE_CELLS = 128

CSS = f"""
Screen {{
    background: {BLACK};
    color: {AMBER};
}}

#topbar {{
    height: 2;
    border-bottom: solid {AMBER_DIM};
    padding: 0 1;
}}

#title {{
    width: 18;
    color: {AMBER_GLOW};
    text-style: bold;
}}

#progress_bar {{
    width: 1fr;
}}

#counter {{
    width: 108;
    text-align: left;
    color: {AMBER_DIM};
}}

#grid {{
    grid-size: 2 2;
    grid-gutter: 0 1;
    padding: 0 1;
    height: 1fr;
}}

.panel {{
    border: solid {AMBER_DIM};
    padding: 0;
    layers: base overlay;
}}

.panel:hover {{
    border: solid {AMBER};
}}

.panel.expanded {{
    border: double {AMBER_GLOW};
}}

.panel-active {{
    border: double {ORANGE_ACTIVE};
}}

.panel-pass {{
    border: solid {GREEN_OK};
}}

.panel-fail {{
    border: solid {RED_BRIGHT};
}}

.panel.expanded.panel-active {{
    border: double {ORANGE_ACTIVE};
}}

.panel.expanded.panel-pass {{
    border: double {GREEN_OK};
}}

.panel.expanded.panel-fail {{
    border: double {RED_BRIGHT};
}}

.panel-scroll {{
    height: 1fr;
    padding: 0;
    layer: base;
}}

.active-runner-cell {{
    position: absolute;
    layer: overlay;
    width: 1;
    height: 1;
    background: transparent;
    display: none;
}}

#metrics_bar {{
    height: auto;
    border-top: solid {AMBER_DIM};
    padding: 0;
}}

#metrics_layout {{
    height: auto;
}}

#metrics_side_label {{
    width: 8;
    height: 100%;
    border-right: double {AMBER_DIM};
    padding: 0 0;
    color: {AMBER_GLOW};
    text-style: bold;
    text-align: center;
    content-align: center middle;
}}

#metrics_cards {{
    height: auto;
    width: 1fr;
}}

.metric-card {{
    width: 1fr;
    height: auto;
    border: solid {AMBER_DIM};
    padding: 0 0;
    margin: 0;
    text-align: center;
    content-align: center top;
}}

.metric-card:hover {{
    border: double {AMBER_GLOW};
}}

.metric-card-good {{
    border: solid {GREEN_OK};
}}

.metric-card-warn {{
    border: solid {AMBER};
}}

.metric-card-bad {{
    border: solid {RED_BRIGHT};
}}

.metric-card-idle {{
    border: solid {AMBER_DIM};
}}

.metrics-footer {{
    display: none;
}}

#boot_overlay {{
    layer: overlay;
    width: 100%;
    height: 100%;
    align: center middle;
    background: {BLACK};
}}

#rerun_button {{
    width: 24;
    text-align: center;
    border: solid {AMBER_DIM};
    color: {AMBER_DIM};
}}

#rerun_button.enabled {{
    border: solid {RED_BRIGHT};
    color: {RED_BRIGHT};
}}

#rerun_button.running {{
    border: double {ORANGE_ACTIVE};
    color: {ORANGE_ACTIVE};
}}
"""

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
EVENT_PREFIX = "KFS_EVENT|"
KNOWN_SECTIONS = {
    "LINT",
    "SETUP",
    "TESTS",
    "ARCHITECTURE TESTS",
    "STABILITY TESTS",
    "REJECTION TESTS",
    "BOOT TESTS",
}
SECTION_TO_PANEL = {
    "LINT": 0,
    "SETUP": 0,
    "TESTS": 1,
    "ARCHITECTURE TESTS": 2,
    "STABILITY TESTS": 2,
    "REJECTION TESTS": 2,
    "BOOT TESTS": 3,
}
PANEL_TITLES = ["LINT / SETUP", "TESTS", "ARCHITECTURE / STABILITY / REJECTION", "BOOT TESTS"]
PANEL_SECTIONS = {
    0: ["LINT", "SETUP"],
    1: ["TESTS"],
    2: ["ARCHITECTURE TESTS", "STABILITY TESTS", "REJECTION TESTS"],
    3: ["BOOT TESTS"],
}
SECTION_LABELS = {
    "LINT": "LINT",
    "SETUP": "SETUP",
    "TESTS": "TESTS",
    "ARCHITECTURE TESTS": "ARCH",
    "STABILITY TESTS": "STABILITY",
    "REJECTION TESTS": "REJECTION",
    "BOOT TESTS": "BOOT",
}
BOOT_FRAMES = [
    """\
╔══════════════════════════════════════════╗
║         KFS KERNEL TEST SYSTEM           ║
║         BIOS v2.0 — POST CHECK           ║
╚══════════════════════════════════════════╝

  Detecting CPU ........ i686 OK
  Memory check ......... 640K OK
  Storage .............. /dev/sda OK
  Loading GRUB ......... ▓░░░░░░░░░
""",
    """\
╔══════════════════════════════════════════╗
║         KFS KERNEL TEST SYSTEM           ║
║      *** LAUNCHING TEST SUITE ***        ║
╚══════════════════════════════════════════╝

  arch: i386
  mode: AUTOMATED TEST RUN
""",
]
DEMO_LINES = """KFS_EVENT|suite|i386
KFS_EVENT|suite_total|6
KFS_EVENT|section_total|LINT|1
KFS_EVENT|section_total|SETUP|3
KFS_EVENT|section_total|ARCHITECTURE TESTS|1
KFS_EVENT|section_total|BOOT TESTS|2
KFS_EVENT|declare|LINT|-|Run lint checks|-|-
KFS_EVENT|declare|SETUP|-|Rebuild the container toolchain image|-|-
KFS_EVENT|declare|SETUP|-|Verify tools exist|-|-
KFS_EVENT|declare|SETUP|-|Verify host test tools exist|-|-
KFS_EVENT|section|LINT
KFS_EVENT|start|LINT|-|Run lint checks|-|-
Run lint checks PASS
KFS_EVENT|result|LINT|-|Run lint checks|pass|-|-
KFS_EVENT|declare|ARCHITECTURE TESTS|-|kernel architecture files stay in allowed directories|scripts/architecture-tests/kernel-architecture.sh|target-tree-has-kernel-root
KFS_EVENT|declare|BOOT TESTS|-|runtime reaches Rust kmain|scripts/boot-tests/release-kmain-symbol.sh|runtime-reaches-kmain
KFS_EVENT|declare|BOOT TESTS|-|runtime markers appear in the expected order|scripts/boot-tests/runtime-markers.sh|runtime-markers-ordered
KFS_EVENT|section|SETUP
KFS_EVENT|start|SETUP|-|Rebuild the container toolchain image|-|-
Rebuild the container toolchain image PASS
KFS_EVENT|result|SETUP|-|Rebuild the container toolchain image|pass|-|-
KFS_EVENT|start|SETUP|-|Verify tools exist|-|-
Verify tools exist PASS
KFS_EVENT|result|SETUP|-|Verify tools exist|pass|-|-
KFS_EVENT|start|SETUP|-|Verify host test tools exist|-|-
Verify host test tools exist PASS
KFS_EVENT|result|SETUP|-|Verify host test tools exist|pass|-|-
KFS_EVENT|section|ARCHITECTURE TESTS
KFS_EVENT|start|ARCHITECTURE TESTS|-|kernel architecture files stay in allowed directories|scripts/architecture-tests/kernel-architecture.sh|target-tree-has-kernel-root
kernel architecture files stay in allowed directories PASS
KFS_EVENT|result|ARCHITECTURE TESTS|-|kernel architecture files stay in allowed directories|pass|scripts/architecture-tests/kernel-architecture.sh|target-tree-has-kernel-root
KFS_EVENT|section|BOOT TESTS
KFS_EVENT|start|BOOT TESTS|-|runtime reaches Rust kmain|scripts/boot-tests/release-kmain-symbol.sh|runtime-reaches-kmain
runtime reaches Rust kmain PASS
KFS_EVENT|result|BOOT TESTS|-|runtime reaches Rust kmain|pass|scripts/boot-tests/release-kmain-symbol.sh|runtime-reaches-kmain
KFS_EVENT|start|BOOT TESTS|-|runtime markers appear in the expected order|scripts/boot-tests/runtime-markers.sh|runtime-markers-ordered
runtime markers appear in the expected order PASS
KFS_EVENT|result|BOOT TESTS|-|runtime markers appear in the expected order|pass|scripts/boot-tests/runtime-markers.sh|runtime-markers-ordered
KFS_EVENT|summary|pass""".splitlines()


def strip_ansi(value: str) -> str:
    return ANSI_ESCAPE.sub("", value)


def format_subgroup_title(subgroup: str) -> Optional[str]:
    if subgroup == "-":
        return None
    return subgroup.replace("/", " / ").replace("-", " ").replace("_", " ").upper()


@dataclass
class TestItem:
    section: str
    subgroup: str
    name: str
    status: str = "wait"
    error_log: list[str] = field(default_factory=list)
    script_path: Optional[str] = None
    test_case: Optional[str] = None


class BootOverlay(Static):
    def compose(self) -> ComposeResult:
        yield Static("", id="boot_text")

    def set_frame(self, text: str) -> None:
        self.query_one("#boot_text", Static).update(f"[{AMBER}]{text}[/]")


class RerunButton(Static):
    can_focus = True

    def set_state(self, enabled: bool, running: bool, label: str) -> None:
        self.remove_class("enabled")
        self.remove_class("running")
        if running:
            self.add_class("running")
        elif enabled:
            self.add_class("enabled")
        self.update(label)

    def on_click(self) -> None:
        self.app.action_rerun_failed()


class MetricCardWidget(Widget):
    can_focus = True

    def __init__(self, card_index: int, **kwargs):
        super().__init__(**kwargs)
        self.card_index = card_index
        self.card_text = f"[{AMBER_DIM}]No data[/]"

    def set_card(self, markup: str, tooltip: Optional[str]) -> None:
        self.card_text = markup
        self.tooltip = tooltip
        self.refresh(layout=True)

    def render(self) -> Text:
        text = Text.from_markup(self.card_text)
        text.justify = "center"
        return text

    def get_content_height(self, container: Size, viewport: Size, width: int) -> int:
        return self.card_text.count("\n") + 1

    def on_enter(self) -> None:
        return None

    def on_focus(self) -> None:
        return None

    def on_leave(self) -> None:
        return None

    def on_blur(self) -> None:
        return None


class TestPanel(Vertical):
    can_focus = True

    def __init__(self, panel_id: int, title: str, **kwargs):
        super().__init__(**kwargs)
        self.panel_id = panel_id
        self.base_title = title
        self.items: list[TestItem] = []
        self.visual_state = "idle"
        self.heading = self.base_title
        self.summary_lines: list[str] = []
        self.border_title = self._format_heading(self.heading)
        self.border_subtitle = self._format_summary(self.summary_lines)

    def _state_color(self) -> str:
        if self.visual_state == "active":
            return ORANGE_ACTIVE
        if self.visual_state == "pass":
            return GREEN_OK
        if self.visual_state == "fail":
            return RED_BRIGHT
        return AMBER_GLOW

    def _summary_color(self) -> str:
        if self.visual_state == "active":
            return ORANGE_ACTIVE
        if self.visual_state == "pass":
            return GREEN_OK
        if self.visual_state == "fail":
            return RED_BRIGHT
        return AMBER_DIM

    def _format_heading(self, heading: str) -> Text:
        if not heading:
            return Text("")
        color = self._state_color()
        return Text.from_markup(f"[{BLACK} on {color}][b] {heading} [/b][/]")

    def _format_summary(self, summary_lines: list[str]) -> Text:
        if not summary_lines:
            return Text("")
        color = self._summary_color()
        plain_summary = "   ".join(summary_lines)
        return Text.from_markup(f"[{color}]{plain_summary}[/]")

    def _apply_visual_state(self) -> None:
        for class_name in ("panel-active", "panel-pass", "panel-fail"):
            self.remove_class(class_name)

        if self.visual_state == "active":
            self.add_class("panel-active")
        elif self.visual_state == "pass":
            self.add_class("panel-pass")
        elif self.visual_state == "fail":
            self.add_class("panel-fail")

        self._apply_border_style()
        self.border_title = self._format_heading(self.heading)
        self.border_subtitle = self._format_summary(self.summary_lines)

    def _apply_border_style(self) -> None:
        if self.visual_state == "active":
            style = "double"
            color = ORANGE_BASE
        elif self.visual_state == "pass":
            style = "solid"
            color = GREEN_OK
        elif self.visual_state == "fail":
            style = "solid"
            color = RED_BRIGHT
        else:
            style = "solid"
            color = AMBER_DIM

        self.styles.border_top = (style, color)
        self.styles.border_right = (style, color)
        self.styles.border_bottom = (style, color)
        self.styles.border_left = (style, color)

    def compose(self) -> ComposeResult:
        with VerticalScroll(id=f"panel_scroll_{self.panel_id}", classes="panel-scroll"):
            yield Static("", id=f"panel_content_{self.panel_id}")

    def declare_item(
        self,
        section: str,
        subgroup: str,
        name: str,
        script_path: Optional[str] = None,
        test_case: Optional[str] = None,
    ) -> bool:
        if self._find_item(section, subgroup, name) is None:
            self.items.append(
                TestItem(
                    section=section,
                    subgroup=subgroup,
                    name=name,
                    script_path=script_path,
                    test_case=test_case,
                )
            )
            self._refresh()
            return True
        item = self._find_item(section, subgroup, name)
        if item is not None:
            item.script_path = script_path or item.script_path
            item.test_case = test_case or item.test_case
        return False

    def mark_running(
        self,
        section: str,
        subgroup: str,
        name: str,
        script_path: Optional[str] = None,
        test_case: Optional[str] = None,
    ) -> None:
        item = self._get_or_create(section, subgroup, name, script_path, test_case)
        item.status = "run"
        self._refresh()
        self._scroll_to_item(section, subgroup, name)

    def complete_item(
        self,
        section: str,
        subgroup: str,
        name: str,
        passed: bool,
        error_log: list[str],
        script_path: Optional[str] = None,
        test_case: Optional[str] = None,
    ) -> None:
        item = self._get_or_create(section, subgroup, name, script_path, test_case)
        item.status = "pass" if passed else "fail"
        item.error_log = error_log
        self._refresh()
        self._scroll_to_item(section, subgroup, name)

    def update_stats(self, heading: str, summary_lines: list[str], state: str) -> None:
        self.heading = heading
        self.summary_lines = list(summary_lines)
        self.visual_state = state
        self._apply_visual_state()

    def _find_item(self, section: str, subgroup: str, name: str) -> Optional[TestItem]:
        for item in self.items:
            if item.section == section and item.subgroup == subgroup and item.name == name:
                return item
        return None

    def _get_or_create(
        self,
        section: str,
        subgroup: str,
        name: str,
        script_path: Optional[str] = None,
        test_case: Optional[str] = None,
    ) -> TestItem:
        item = self._find_item(section, subgroup, name)
        if item is None:
            item = TestItem(
                section=section,
                subgroup=subgroup,
                name=name,
                script_path=script_path,
                test_case=test_case,
            )
            self.items.append(item)
        else:
            item.script_path = script_path or item.script_path
            item.test_case = test_case or item.test_case
        return item

    def _scroll_to_item(self, section: str, subgroup: str, name: str) -> None:
        line_index = self._line_index_for_item(section, subgroup, name)
        if line_index is None:
            return

        scroll = self.query_one(f"#panel_scroll_{self.panel_id}", VerticalScroll)
        scroll_to = max(line_index - 1, 0)
        scroll.call_after_refresh(
            scroll.scroll_to,
            y=scroll_to,
            animate=False,
            force=True,
            immediate=True,
        )

    def _line_index_for_item(self, section: str, subgroup: str, name: str) -> Optional[int]:
        line_index = 0
        current_section = None
        current_subgroup = None

        for item in self.items:
            if item.section != current_section:
                if current_section is not None:
                    line_index += 1
                current_section = item.section
                current_subgroup = None
                line_index += 1

            if item.subgroup != current_subgroup:
                current_subgroup = item.subgroup
                if format_subgroup_title(item.subgroup) is not None:
                    line_index += 1

            if item.section == section and item.subgroup == subgroup and item.name == name:
                return line_index

            line_index += 1
            if item.status == "fail":
                line_index += len(item.error_log)

        return None

    def _refresh(self) -> None:
        lines = []
        current_section = None
        current_subgroup = None
        for item in self.items:
            if item.section != current_section:
                current_section = item.section
                current_subgroup = None
                if lines:
                    lines.append("")
                lines.append(f"[{AMBER_DIM}]{SECTION_LABELS.get(item.section, item.section)}[/]")
            if item.subgroup != current_subgroup:
                current_subgroup = item.subgroup
                subgroup_title = format_subgroup_title(item.subgroup)
                if subgroup_title is not None:
                    lines.append(f"[{AMBER_FAINT}]  {subgroup_title}[/]")
            if item.status == "wait":
                lines.append(f"[{AMBER_DIM}]· {item.name}[/]")
            elif item.status == "run":
                lines.append(f"[{AMBER}]▶ {item.name}[/]")
            elif item.status == "pass":
                lines.append(f"[{GREEN_OK}]✓[/] [{AMBER}]{item.name}[/]")
            else:
                lines.append(f"[{RED_BRIGHT}]✗[/] [{RED_BRIGHT}]{item.name}[/]")
                for line in item.error_log:
                    lines.append(f"  [{RED_DIM}]{line}[/]")

        self.query_one(f"#panel_content_{self.panel_id}", Static).update(
            "\n".join(lines) if lines else f"[{AMBER_DIM}]Waiting...[/]"
        )

    def on_click(self) -> None:
        self.app.toggle_panel(self.panel_id)


class MetricsBar(Vertical):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.cards = []

    @staticmethod
    def _tone_color(tone: str) -> str:
        if tone == "good":
            return GREEN_OK
        if tone == "warn":
            return AMBER
        if tone == "bad":
            return RED_BRIGHT
        return AMBER_DIM

    def compose(self) -> ComposeResult:
        with Horizontal(id="metrics_layout"):
            yield Static("D\nO\nR\nA", id="metrics_side_label")
            with Horizontal(id="metrics_cards"):
                for index in range(4):
                    yield MetricCardWidget(index, id=f"metric_card_{index}", classes="metric-card")

    def _status_chip(self, card) -> str:
        color = self._tone_color(card.tone)
        label = card.tier if card.tone != "idle" else "NO DATA"
        return f"[black on {color}] {label} [/]"

    def _tier_labels(self, card) -> str:
        color = self._tone_color(card.tone)
        labels = ["LOW", "MED", "HIGH", "ELITE"]
        parts = []
        for label in labels:
            if label == card.tier and card.tone != "idle":
                parts.append(f"[bold {color}]{label}[/]")
            else:
                parts.append(f"[{AMBER_DIM}]{label}[/]")
        return "  ".join(parts)

    @staticmethod
    def _metric_tooltip(card) -> Text:
        info = {
            "DF": (
                "Deploy Freq",
                "How often changes land successfully in a green run.",
                "Higher is better.",
                "LOW means rare delivery. ELITE means very frequent delivery.",
            ),
            "LT": (
                "Lead Time",
                "How long a change takes to go from commit to green integration.",
                "Lower is better.",
                "LOW means slow delivery. ELITE means changes land quickly.",
            ),
            "CFR": (
                "Change Fail",
                "How many delivered changes cause a failing run.",
                "Lower is better.",
                "LOW means many failures. ELITE means failures are rare.",
            ),
            "MTTR": (
                "MTTR",
                "How long it takes to recover after a failing run.",
                "Lower is better.",
                "LOW means recovery is slow. ELITE means recovery is fast.",
            ),
        }
        title, meaning, direction, tiers = info.get(
            card.key,
            (card.label, "Metric definition unavailable.", "", ""),
        )
        tooltip = Text()
        tooltip.append(f"{title}\n", style=f"bold {AMBER_GLOW}")
        tooltip.append("\n")
        tooltip.append("WHAT\n", style=f"bold {GREEN_OK}")
        tooltip.append(f"  {meaning}\n")
        if direction:
            tooltip.append("\n")
            tooltip.append("HOW TO READ\n", style=f"bold {AMBER}")
            tooltip.append(f"  {direction}\n")
        if tiers:
            tooltip.append("\n")
            tooltip.append("BANDS\n", style=f"bold {AMBER}")
            tooltip.append(f"  {tiers}\n")
        tooltip.append("\n")
        tooltip.append("THRESHOLDS\n", style=f"bold {AMBER_DIM}")
        tooltip.append(f"  {card.explain}")
        return tooltip

    def _render_threshold_graph(self, card) -> tuple[str, str]:
        colors = [RED_BRIGHT] * 3 + [AMBER] * 3 + [AMBER_GLOW] * 3 + [GREEN_OK] * 3
        marker_index = card.gauge.find("◆")
        scale_parts = []
        for index, color in enumerate(colors):
            scale_parts.append(f"[{color}]■[/]")
        pointer_prefix = " " * max(marker_index, 0)
        pointer_line = (
            f"{pointer_prefix}[{colors[max(marker_index, 0)]}]▲[/]" if marker_index >= 0 else ""
        )
        return "".join(scale_parts), pointer_line

    def _delta_label(self, card) -> str:
        if card.delta == "flat":
            return f"[{AMBER_DIM}]=[/]"
        if card.delta == "n/a":
            return f"[{AMBER_DIM}]n/a[/]"
        positive = card.delta.startswith("↑")
        color = GREEN_OK if positive else RED_BRIGHT
        return f"[{color}]{card.delta}[/]"

    def _format_card(self, card, baseline_label: str) -> str:
        color = self._tone_color(card.tone)
        scale_line, pointer_line = self._render_threshold_graph(card)
        return (
            f"[bold {AMBER}]{card.label}[/]\n"
            f"[bold {color}]{card.value}[/]  {self._delta_label(card)}\n"
            f"{self._tier_labels(card)}\n"
            f"{scale_line}\n"
            f"{pointer_line}"
        )

    def update_metrics(
        self,
        snapshot: DashboardSnapshot,
        arch: str,
        active_section: Optional[str],
        elapsed_seconds: float,
        passed: int,
        failed: int,
        discovered_total: int,
        suite_total: int,
        finished: bool,
    ) -> None:
        self.cards = list(snapshot.cards)

        for index in range(4):
            widget = self.query_one(f"#metric_card_{index}", MetricCardWidget)
            for class_name in (
                "metric-card-good",
                "metric-card-warn",
                "metric-card-bad",
                "metric-card-idle",
            ):
                widget.remove_class(class_name)

            if index < len(snapshot.cards):
                card = snapshot.cards[index]
                card_text = self._format_card(card, snapshot.baseline_label)
                widget.set_card(
                    card_text,
                    self._metric_tooltip(card),
                )
                widget.add_class(f"metric-card-{card.tone}")
            else:
                widget.set_card(f"[{AMBER_DIM}]No data[/]", "No metric data yet.")
                widget.add_class("metric-card-idle")


class KFSApp(App):
    CSS = CSS
    BINDINGS = [
        Binding("r", "rerun_failed", "Rerun failed"),
        Binding("q", "quit", "Quit"),
        Binding("escape", "quit", "Quit"),
    ]

    def __init__(self, mode: str, arch: str, make_target: str, **kwargs):
        super().__init__(**kwargs)
        self.mode = mode
        self.arch = arch
        self.make_target = make_target
        self.current_section: Optional[str] = None
        self.suite_total = 0
        self.discovered_total = 0
        self.passed = 0
        self.failed = 0
        self.active_runner_started_at: Optional[float] = None
        self.active_panel: Optional[int] = None
        self.expanded_panel: Optional[int] = None
        self.done = False
        self.boot_done = False
        self.last_failed_item: Optional[tuple[int, str, str, str]] = None
        self.pending_error_log: list[str] = []
        self.pending_failure_meta: tuple[Optional[str], Optional[str]] = (None, None)
        self.last_failed_rerun: Optional[tuple[int, str, str, str, str, str]] = None
        self.rerun_in_progress = False
        self.seen_protocol_event = False
        self.section_totals: dict[str, int] = {}
        self.section_done: dict[str, int] = {}
        self.section_passed: dict[str, int] = {}
        self.section_failed: dict[str, int] = {}
        self.active_cells: list[Static] = []
        self.repo_root = repo_root_for(__file__)
        self.db_path = default_db_path(self.repo_root)
        self.current_branch = "HEAD"
        self.metrics_snapshot = DashboardSnapshot(
            scope_branch="pending",
            scope_state="unknown",
            baseline_label="pending",
            assumption="collecting history",
            cards=[],
        )
        self.run_started_at: Optional[float] = None

    def compose(self) -> ComposeResult:
        with Horizontal(id="topbar"):
            yield Static("◈ KFS TEST RUNNER", id="title")
            yield Static("", id="progress_bar")
            yield Static("", id="counter")
            yield RerunButton(f"[{AMBER_DIM}]RERUN LAST FAIL (R)[/]", id="rerun_button")
        with Grid(id="grid"):
            for index, title in enumerate(PANEL_TITLES):
                yield TestPanel(index, title, id=f"panel_{index}", classes="panel")
        for index in range(MAX_ACTIVE_CELLS):
            yield Static("", id=f"active_cell_{index}", classes="active-runner-cell")
        yield MetricsBar(id="metrics_bar")
        yield BootOverlay(id="boot_overlay")

    def on_mount(self) -> None:
        self.active_cells = [
            self.query_one(f"#active_cell_{index}", Static) for index in range(MAX_ACTIVE_CELLS)
        ]
        self.current_branch = (
            subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=False,
            ).stdout.strip()
            or "HEAD"
        )
        self.run_started_at = time.monotonic()
        self._update_top_status()
        self._update_rerun_button()
        self._refresh_metrics_display(reload_snapshot=True)
        self.set_interval(RUNNER_TICK_SECS, self._tick)
        self._boot_and_run()

    @work(thread=True)
    def _boot_and_run(self) -> None:
        overlay = self.query_one("#boot_overlay", BootOverlay)
        for frame in BOOT_FRAMES:
            self.call_from_thread(overlay.set_frame, frame)
            time.sleep(0.45)
        manifest_loaded = False
        if self.mode == "make":
            manifest_loaded = self._prefetch_manifest()
        self.call_from_thread(self._hide_boot)
        time.sleep(0.2)

        if self.mode == "demo":
            self._consume_lines(DEMO_LINES)
        elif self.mode == "stdin":
            self._consume_lines(sys.stdin)
        else:
            env = os.environ.copy()
            env["KFS_TUI_PROTOCOL"] = "1"
            env["KFS_COLOR"] = "0"
            if manifest_loaded:
                env["KFS_TUI_SKIP_MANIFEST"] = "1"
            process = subprocess.Popen(
                ["make", self.make_target, f"arch={self.arch}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                env=env,
            )
            assert process.stdout is not None
            self._consume_lines(process.stdout)
            rc = process.wait()
            if not self.done:
                self.call_from_thread(self._finish, rc == 0)

    def _prefetch_manifest(self) -> bool:
        env = os.environ.copy()
        env["KFS_TUI_PROTOCOL"] = "1"
        env["KFS_COLOR"] = "0"

        process = subprocess.run(
            ["bash", "scripts/test-host.sh", "--manifest", self.arch],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
            check=False,
        )

        for line in process.stdout.splitlines():
            self._process_line(line)

        return process.returncode == 0

    def _hide_boot(self) -> None:
        self.query_one("#boot_overlay").display = False
        self.boot_done = True
        self._refresh_metrics_display()

    def _consume_lines(self, stream) -> None:
        for raw_line in stream:
            self._process_line(raw_line.rstrip("\n"))
        self._flush_pending_item()

    def _process_line(self, raw: str) -> None:
        line = strip_ansi(raw)

        if line.startswith(EVENT_PREFIX):
            self._process_event(line)
            return

        if line.startswith("  ") and self.last_failed_item is not None:
            detail = line.strip()
            if detail:
                self.pending_error_log.append(detail)
            return

        self._flush_pending_item()

        stripped = line.strip()
        if (
            not stripped
            or stripped.startswith("=")
            or stripped == "KFS TESTS"
            or stripped.startswith("arch:")
        ):
            return

        if self.seen_protocol_event and (stripped.endswith(" PASS") or stripped.endswith(" FAIL")):
            return

        if stripped.endswith(" PASS") or stripped.endswith(" FAIL"):
            passed = stripped.endswith(" PASS")
            name = stripped[:-5].strip()
            section = self.current_section or "SETUP"
            subgroup = "-"
            panel_index = SECTION_TO_PANEL.get(self.current_section or "SETUP", 0)
            if passed:
                self.call_from_thread(
                    self._complete_item, panel_index, section, subgroup, name, True, []
                )
            else:
                self.last_failed_item = (panel_index, section, subgroup, name)
                self.pending_error_log = []
                self.pending_failure_meta = (None, None)
            return

        if stripped in KNOWN_SECTIONS:
            self.current_section = stripped

    def _process_event(self, line: str) -> None:
        parts = line.split("|")
        kind = parts[1] if len(parts) > 1 else ""
        self.seen_protocol_event = True

        if kind != "result":
            self._flush_pending_item()

        if kind == "suite":
            if len(parts) >= 4:
                self.call_from_thread(self._set_suite_total, int(parts[3]))
            return
        if kind == "suite_total" and len(parts) >= 3:
            self.call_from_thread(self._set_suite_total, int(parts[2]))
            return
        if kind == "section_total" and len(parts) >= 4:
            self.call_from_thread(self._set_section_total, parts[2], int(parts[3]))
            return
        if kind == "section" and len(parts) >= 3:
            self.current_section = parts[2]
            return
        if kind == "declare" and len(parts) >= 4:
            if len(parts) >= 5:
                section, subgroup, name = parts[2], parts[3], parts[4]
            else:
                section, subgroup, name = parts[2], "-", parts[3]
            script_path = parts[5] if len(parts) >= 6 and parts[5] != "-" else None
            test_case = parts[6] if len(parts) >= 7 and parts[6] != "-" else None
            self.current_section = section
            self.call_from_thread(
                self._declare_item,
                SECTION_TO_PANEL.get(section, 0),
                section,
                subgroup,
                name,
                script_path,
                test_case,
            )
            return
        if kind == "start" and len(parts) >= 4:
            if len(parts) >= 5:
                section, subgroup, name = parts[2], parts[3], parts[4]
            else:
                section, subgroup, name = parts[2], "-", parts[3]
            script_path = parts[5] if len(parts) >= 6 and parts[5] != "-" else None
            test_case = parts[6] if len(parts) >= 7 and parts[6] != "-" else None
            self.current_section = section
            self.call_from_thread(
                self._mark_running,
                SECTION_TO_PANEL.get(section, 0),
                section,
                subgroup,
                name,
                script_path,
                test_case,
            )
            return
        if kind == "result" and len(parts) >= 5:
            if len(parts) >= 6:
                section, subgroup, name, status = parts[2], parts[3], parts[4], parts[5]
            else:
                section, subgroup, name, status = parts[2], "-", parts[3], parts[4]
            script_path = parts[6] if len(parts) >= 7 and parts[6] != "-" else None
            test_case = parts[7] if len(parts) >= 8 and parts[7] != "-" else None
            self.current_section = section
            if status == "pass":
                self._flush_pending_item()
                self.call_from_thread(
                    self._complete_item,
                    SECTION_TO_PANEL.get(section, 0),
                    section,
                    subgroup,
                    name,
                    True,
                    [],
                    script_path,
                    test_case,
                )
            elif status == "fail":
                self._flush_pending_item()
                self.last_failed_item = (SECTION_TO_PANEL.get(section, 0), section, subgroup, name)
                self.pending_error_log = []
                self.pending_failure_meta = (script_path, test_case)
            return
        if kind == "summary" and len(parts) >= 3:
            self.call_from_thread(self._finish, parts[2] == "pass")

    def _flush_pending_item(self) -> None:
        if self.last_failed_item is None:
            return
        panel_index, section, subgroup, name = self.last_failed_item
        log = list(self.pending_error_log)
        script_path, test_case = self.pending_failure_meta
        self.last_failed_item = None
        self.pending_error_log = []
        self.pending_failure_meta = (None, None)
        self.call_from_thread(
            self._complete_item,
            panel_index,
            section,
            subgroup,
            name,
            False,
            log,
            script_path,
            test_case,
        )

    def _set_suite_total(self, total: int) -> None:
        self.suite_total = total
        self._update_bar()
        self._update_panel_summaries()

    def _set_section_total(self, section: str, total: int) -> None:
        self.section_totals[section] = total
        self._update_bar()
        self._update_panel_summaries()

    def _declare_item(
        self,
        panel_index: int,
        section: str,
        subgroup: str,
        name: str,
        script_path: Optional[str] = None,
        test_case: Optional[str] = None,
    ) -> None:
        created = self.query_one(f"#panel_{panel_index}", TestPanel).declare_item(
            section,
            subgroup,
            name,
            script_path,
            test_case,
        )
        if created:
            self.discovered_total += 1
            if section not in self.section_totals:
                self.section_totals[section] = self.section_totals.get(section, 0) + 1
            self._update_bar()
            self._update_panel_summaries()

    def _current_runner_progress(self) -> float:
        if self.active_runner_started_at is None:
            return 0.0
        return ((time.monotonic() - self.active_runner_started_at) / ACTIVE_CYCLE_SECS) % 1.0

    def _hide_active_runner(self) -> None:
        for cell in self.active_cells:
            cell.display = False

    def _runner_path(self, width: int, height: int) -> list[tuple[int, int]]:
        path: list[tuple[int, int]] = []
        for x in range(width):
            path.append((x, 0))
        for y in range(1, height):
            path.append((width - 1, y))
        for x in range(width - 2, -1, -1):
            path.append((x, height - 1))
        for y in range(height - 2, 0, -1):
            path.append((0, y))
        return path

    def _sync_active_runner(self) -> None:
        if not self.active_cells:
            return

        if self.active_panel is None:
            self._hide_active_runner()
            return

        try:
            panel = self.query_one(f"#panel_{self.active_panel}", TestPanel)
        except Exception:
            self._hide_active_runner()
            return
        if not panel.display or panel.visual_state != "active":
            self._hide_active_runner()
            return

        width = int(panel.region.width)
        height = int(panel.region.height)
        if width < 2 or height < 2:
            self._hide_active_runner()
            return

        path = self._runner_path(width, height)
        perimeter = len(path)
        if perimeter <= 0:
            self._hide_active_runner()
            return

        segment_len = min(MAX_ACTIVE_CELLS, max(8, int(perimeter * ACTIVE_SEGMENT_RATIO)))
        lead_len = max(2, segment_len // 5)
        head = int(self._current_runner_progress() * perimeter) % perimeter

        points: list[tuple[int, int]] = []
        for offset in range(segment_len):
            points.append(path[(head + offset) % perimeter])

        base_x = int(panel.region.x)
        base_y = int(panel.region.y)
        for index, cell in enumerate(self.active_cells):
            if index >= len(points):
                cell.display = False
                continue

            x, y = points[index]
            glyph = "█" if index < lead_len else "▓"
            color = ORANGE_HEAD if index < lead_len else ORANGE_ACTIVE
            cell.styles.offset = (base_x + x, base_y + y)
            cell.update(f"[bold {color}]{glyph}[/]")
            cell.display = True

    def _mark_running(
        self,
        panel_index: int,
        section: str,
        subgroup: str,
        name: str,
        script_path: Optional[str] = None,
        test_case: Optional[str] = None,
    ) -> None:
        if self.active_panel != panel_index or self.active_runner_started_at is None:
            self.active_runner_started_at = time.monotonic()
        self.active_panel = panel_index
        self.query_one(f"#panel_{panel_index}", TestPanel).mark_running(
            section,
            subgroup,
            name,
            script_path,
            test_case,
        )
        self._update_panel_summaries()
        self._sync_active_runner()

    def _complete_item(
        self,
        panel_index: int,
        section: str,
        subgroup: str,
        name: str,
        passed: bool,
        error_log: list[str],
        script_path: Optional[str] = None,
        test_case: Optional[str] = None,
    ) -> None:
        panel = self.query_one(f"#panel_{panel_index}", TestPanel)
        item = panel._find_item(section, subgroup, name)
        previous_status = item.status if item is not None else None
        panel.complete_item(section, subgroup, name, passed, error_log, script_path, test_case)
        if previous_status not in {"pass", "fail"}:
            if passed:
                self.passed += 1
                self.section_passed[section] = self.section_passed.get(section, 0) + 1
            else:
                self.failed += 1
                self.section_failed[section] = self.section_failed.get(section, 0) + 1
            self.section_done[section] = self.section_done.get(section, 0) + 1
            self._update_bar()
            self._update_panel_summaries()
        if not passed and script_path and test_case:
            self.last_failed_rerun = (panel_index, section, subgroup, name, script_path, test_case)
        self._update_rerun_button()

    def _update_bar(self) -> None:
        total = max(self.suite_total or self.discovered_total, self.passed + self.failed, 1)
        done = self.passed + self.failed
        filled = int((done / total) * 40)
        pct = int((done / total) * 100)
        color = RED_BRIGHT if self.failed else GREEN_OK if done == total and total > 0 else AMBER
        self.query_one("#progress_bar", Static).update(
            f"[{color}]{'▓' * filled}{'░' * (40 - filled)}[/] [{AMBER}]{pct}%[/]"
        )
        self._update_top_status()
        self._refresh_metrics_display()

    def _update_top_status(self) -> None:
        total = max(self.suite_total or self.discovered_total, self.passed + self.failed, 1)
        done = self.passed + self.failed
        active_label = (
            "FAILED"
            if self.done and self.failed
            else "DONE" if self.done else (self.current_section or "WAITING")
        )
        elapsed = self._elapsed_seconds()
        branch_label = self.current_branch
        if len(branch_label) > 28:
            branch_label = f"{branch_label[:25]}..."
        self.query_one("#counter", Static).update(
            f"[{AMBER}]branch[/]={branch_label}  "
            f"[{AMBER}]arch[/]={self.arch}  "
            f"[{AMBER}]elapsed[/]={elapsed:4.1f}s  "
            f"[{RED_BRIGHT if active_label == 'FAILED' else AMBER}]active[/]={active_label}  "
            f"[{AMBER}]done[/]={done}/{total}  "
            f"[{GREEN_OK}]pass[/]={self.passed}  "
            f"[{RED_BRIGHT}]fail[/]={self.failed}"
        )

    def _update_rerun_button(self) -> None:
        enabled = self.last_failed_rerun is not None and not self.rerun_in_progress
        if self.rerun_in_progress:
            label = f"[bold {ORANGE_ACTIVE}]RERUNNING[/]"
        elif enabled:
            _, _, _, name, _, _ = self.last_failed_rerun
            label = f"[bold {RED_BRIGHT}]RERUN LAST FAIL (R)[/]\n[{RED_BRIGHT}]{name[:22]}[/]"
        else:
            label = f"[{AMBER_DIM}]RERUN LAST FAIL (R)[/]"
        self.query_one("#rerun_button", RerunButton).set_state(
            enabled, self.rerun_in_progress, label
        )

    def _elapsed_seconds(self) -> float:
        if self.run_started_at is None:
            return 0.0
        return max(0.0, time.monotonic() - self.run_started_at)

    def _refresh_metrics_display(self, reload_snapshot: bool = False) -> None:
        if reload_snapshot:
            self.metrics_snapshot = load_dashboard(
                self.db_path, self.repo_root, self.current_branch
            )
        self.query_one("#metrics_bar", MetricsBar).update_metrics(
            snapshot=self.metrics_snapshot,
            arch=self.arch,
            active_section=self.current_section,
            elapsed_seconds=self._elapsed_seconds(),
            passed=self.passed,
            failed=self.failed,
            discovered_total=self.discovered_total,
            suite_total=self.suite_total,
            finished=self.done,
        )

    def _update_panel_summaries(self) -> None:
        for panel_index, sections in PANEL_SECTIONS.items():
            panel_total = sum(self.section_totals.get(section, 0) for section in sections)
            panel_done = sum(self.section_done.get(section, 0) for section in sections)
            panel_pct = int((panel_done / panel_total) * 100) if panel_total else 0
            heading = f"{PANEL_TITLES[panel_index]} [{panel_done}/{panel_total} {panel_pct}%]"
            panel_failed = sum(self.section_failed.get(section, 0) for section in sections)

            if panel_failed > 0:
                state = "fail"
            elif panel_total > 0 and panel_done == panel_total:
                state = "pass"
            elif self.active_panel == panel_index:
                state = "active"
            else:
                state = "idle"

            summary_lines = []
            for section in sections:
                total = self.section_totals.get(section, 0)
                done = self.section_done.get(section, 0)
                pct = int((done / total) * 100) if total else 0
                summary_lines.append(
                    f"{SECTION_LABELS.get(section, section)} {done}/{total} {pct}%"
                )

            self.query_one(f"#panel_{panel_index}", TestPanel).update_stats(
                heading, summary_lines, state
            )

    def _finish(self, passed: bool) -> None:
        self.done = True
        self.active_runner_started_at = None
        self.active_panel = None
        self._update_panel_summaries()
        self._refresh_metrics_display(reload_snapshot=True)
        self._sync_active_runner()
        self._update_top_status()
        self._update_rerun_button()

    def _tick(self) -> None:
        if self.boot_done and not self.done:
            self._update_top_status()
            self._refresh_metrics_display()
            self._sync_active_runner()

    def toggle_panel(self, panel_id: int) -> None:
        if self.expanded_panel == panel_id:
            self.expanded_panel = None
            for index in range(4):
                panel = self.query_one(f"#panel_{index}", TestPanel)
                panel.display = True
                panel.remove_class("expanded")
                panel.styles.column_span = 1
                panel.styles.row_span = 1
            self.call_after_refresh(self._sync_active_runner)
            return

        self.expanded_panel = panel_id
        for index in range(4):
            panel = self.query_one(f"#panel_{index}", TestPanel)
            if index == panel_id:
                panel.display = True
                panel.add_class("expanded")
                panel.styles.column_span = 2
                panel.styles.row_span = 2
            else:
                panel.display = False
        self.call_after_refresh(self._sync_active_runner)

    def action_quit(self) -> None:
        self.exit()

    def action_rerun_failed(self) -> None:
        if self.last_failed_rerun is None or self.rerun_in_progress:
            return
        self._rerun_failed_test()

    @work(thread=True)
    def _rerun_failed_test(self) -> None:
        assert self.last_failed_rerun is not None
        panel_index, section, subgroup, name, script_path, test_case = self.last_failed_rerun
        self.rerun_in_progress = True
        self.call_from_thread(self._update_rerun_button)
        self.call_from_thread(
            self._mark_running,
            panel_index,
            section,
            subgroup,
            name,
            script_path,
            test_case,
        )

        process = subprocess.run(
            ["bash", script_path, self.arch, test_case],
            cwd=self.repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

        log = [line.rstrip() for line in process.stdout.splitlines() if line.strip()]
        self.call_from_thread(
            self._complete_item,
            panel_index,
            section,
            subgroup,
            name,
            process.returncode == 0,
            log,
            script_path,
            test_case,
        )
        self.rerun_in_progress = False
        self.call_from_thread(self._update_rerun_button)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="KFS retro Textual test runner")
    parser.add_argument("--arch", default="i386")
    parser.add_argument("--demo", action="store_true")
    parser.add_argument("--stdin", action="store_true")
    parser.add_argument("--make-target", default="test-plain")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    mode = "demo" if args.demo else "stdin" if args.stdin else "make"
    app = KFSApp(mode=mode, arch=args.arch, make_target=args.make_target)
    app.run()


if __name__ == "__main__":
    main()
