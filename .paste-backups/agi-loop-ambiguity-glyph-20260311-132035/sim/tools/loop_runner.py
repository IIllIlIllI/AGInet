from __future__ import annotations

import json
import os
import subprocess
import time
from collections import deque
from datetime import datetime, UTC
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"
GRAPH_OUT = ROOT / "docs" / "generated-claim-graph.md"
HISTORY_LIMIT = 5

RESET = "\033[0m"
BOLD = "\033[1m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
DIM = "\033[2m"


def clear() -> None:
    os.system("clear")


def use_color() -> bool:
    return os.environ.get("AGINET_NO_COLOR", "0") != "1"


def colorize(text: str, color: str) -> str:
    if not use_color() or not color:
        return text
    return f"{color}{text}{RESET}"


def run_command(args: list[str], root_str: str) -> tuple[int, str]:
    proc = subprocess.run(
        args,
        capture_output=True,
        text=True,
        cwd=root_str,
        env={**os.environ, "PYTHONPATH": root_str},
    )
    output = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode, output.strip()


def load_latest_report() -> dict | None:
    if not LATEST_REPORT.exists():
        return None
    try:
        return json.loads(LATEST_REPORT.read_text(encoding="utf-8"))
    except Exception:
        return None


def top_hypothesis(posteriors: dict) -> tuple[str | None, float]:
    if not posteriors:
        return None, 0.0
    hid = max(posteriors, key=posteriors.get)
    return hid, float(posteriors[hid])


def snapshot_from_report(report: dict | None) -> dict | None:
    if report is None:
        return None
    result = report.get("result", {})
    posteriors = result.get("posterior_by_hypothesis", {})
    top_id, top_score = top_hypothesis(posteriors)
    graph_summary = result.get("claim_graph_summary", {})
    return {
        "run_id": report.get("run_id"),
        "graph_variant": result.get("graph_variant"),
        "top_hypothesis": top_id,
        "top_score": round(top_score, 4),
        "sovereignty_pressure": round(float(result.get("sovereignty_pressure", 0.0)), 4),
        "contamination_flag": result.get("contamination_flag"),
        "contradiction_density": graph_summary.get("contradiction_density"),
    }


def pressure_text(value: float) -> str:
    text = f"{value:.4f}"
    if value >= 0.62:
        return colorize(text, RED)
    if value >= 0.35:
        return colorize(text, YELLOW)
    return colorize(text, GREEN)


def contamination_text(flag: bool) -> str:
    if flag:
        return colorize("True", RED)
    return colorize("False", GREEN)


def contradiction_text(value) -> str:
    if value is None:
        return "-"
    try:
        v = float(value)
    except Exception:
        return str(value)
    text = f"{v:.4f}"
    if v >= 0.30:
        return colorize(text, RED)
    if v >= 0.15:
        return colorize(text, YELLOW)
    return colorize(text, GREEN)


def status_text(ok: bool) -> str:
    return colorize("ok", GREEN) if ok else colorize("fail", RED)


def maybe_flip_text(current: str | None, previous: str | None) -> str:
    if current is None:
        return "-"
    if previous is not None and current != previous:
        return colorize(current, RED)
    return colorize(current, CYAN)


def glyph(label: str, state: str) -> str:
    palette = {
        "green": GREEN,
        "yellow": YELLOW,
        "red": RED,
        "cyan": CYAN,
    }
    return colorize(label, palette.get(state, ""))


def status_glyph_line(report: dict | None, history: deque) -> str:
    if report is None:
        return "status: -"

    result = report.get("result", {})
    sovereignty = float(result.get("sovereignty_pressure", 0.0))
    contamination = bool(result.get("contamination_flag"))
    contradiction_density = result.get("claim_graph_summary", {}).get("contradiction_density", 0.0)

    flip = False
    if len(history) >= 2:
        flip = history[-1].get("top_hypothesis") != history[-2].get("top_hypothesis")

    s_state = "red" if sovereignty >= 0.62 else "yellow" if sovereignty >= 0.35 else "green"
    c_state = "red" if contamination else "green"

    try:
        d_val = float(contradiction_density)
    except Exception:
        d_val = 0.0
    d_state = "red" if d_val >= 0.30 else "yellow" if d_val >= 0.15 else "green"

    f_state = "red" if flip else "green"

    return "status: " + " ".join([
        f"{glyph('S', s_state)}={sovereignty:.2f}",
        f"{glyph('C', c_state)}={'1' if contamination else '0'}",
        f"{glyph('D', d_state)}={d_val:.2f}",
        f"{glyph('F', f_state)}={'1' if flip else '0'}",
    ])


def render(
    report: dict | None,
    interval: float,
    iteration: int,
    observe_ok: bool,
    graph_ok: bool,
    history: deque,
) -> str:
    now = datetime.now(UTC).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines: list[str] = []
    title = "=== AGINET LOOP ==="
    lines.append(colorize(title, BOLD + CYAN if use_color() else ""))
    lines.append(f"time: {now}")
    lines.append(f"iteration: {iteration}")
    lines.append(f"refresh_interval_sec: {interval}")
    lines.append(f"observe_status: {status_text(observe_ok)}")
    lines.append(f"graph_out_status: {status_text(graph_ok)}")
    lines.append(status_glyph_line(report, history))
    lines.append(colorize("press Ctrl+C to stop", DIM if use_color() else ""))
    lines.append("")

    if report is None:
        lines.append("No latest report found.")
        lines.append(f"Expected file: {LATEST_REPORT}")
        return "\n".join(lines)

    result = report.get("result", {})
    posteriors = result.get("posterior_by_hypothesis", {})
    top_id, top_score = top_hypothesis(posteriors)
    graph_summary = result.get("claim_graph_summary", {})
    support = result.get("claim_graph_support", {})

    lines.append(f"run_id:                {report.get('run_id')}")
    lines.append(f"timestamp_utc:         {report.get('timestamp_utc')}")
    lines.append(f"graph_variant:         {result.get('graph_variant')}")
    lines.append(f"top_hypothesis:        {colorize(str(top_id), CYAN)}")
    lines.append(f"top_score:             {top_score:.4f}")
    lines.append(f"residual_ambiguity:    {result.get('residual_ambiguity')}")
    lines.append(f"sovereignty_pressure:  {pressure_text(float(result.get('sovereignty_pressure', 0.0)))}")
    lines.append(f"contamination_flag:    {contamination_text(bool(result.get('contamination_flag')))}")
    lines.append(f"claim_count:           {graph_summary.get('claim_count')}")
    lines.append(f"edge_count:            {graph_summary.get('edge_count')}")
    lines.append(f"contradiction_density: {contradiction_text(graph_summary.get('contradiction_density'))}")
    lines.append(f"graph_file:            {GRAPH_OUT}")
    lines.append("")

    if support:
        lines.append("Support by hypothesis:")
        for hid in sorted(support.keys()):
            score = support[hid]
            if isinstance(score, float):
                lines.append(f"  {hid:<14} {score:>7.4f}")
            else:
                lines.append(f"  {hid:<14} {score}")
        lines.append("")

    if history:
        lines.append("Recent loop history:")
        lines.append("  run_id                variant                  top            score    sovr     contam")
        prev_top = None
        for item in history:
            run_id = (item.get("run_id") or "-")[-22:]
            variant = str(item.get("graph_variant") or "-")[:22]
            top = maybe_flip_text(str(item.get("top_hypothesis") or "-"), prev_top)
            score = item.get("top_score")
            sovr = pressure_text(float(item.get("sovereignty_pressure") or 0.0))
            contam = contamination_text(bool(item.get("contamination_flag")))
            lines.append(
                f"  {run_id:<22} {variant:<22} {top:<20} "
                f"{str(score):<8} {sovr:<16} {contam:<10}"
            )
            prev_top = str(item.get("top_hypothesis") or "-")
        lines.append("")

    audit = result.get("audit", [])
    if audit:
        lines.append("Recent audit lines:")
        for line in audit[-6:]:
            lines.append(f"  {line}")

    return "\n".join(lines)


def main() -> None:
    interval = float(os.environ.get("AGINET_LOOP_INTERVAL", "5"))
    iteration = 0
    root_str = str(ROOT)
    history: deque = deque(maxlen=HISTORY_LIMIT)

    try:
        while True:
            iteration += 1

            observe_code, _ = run_command(
                ["python", "-B", "-m", "sim.observatory.run_logger"],
                root_str=root_str,
            )

            graph_code, graph_output = run_command(
                ["python", "-B", "-m", "sim.tools.claim_graph_visualizer"],
                root_str=root_str,
            )

            if graph_code == 0:
                GRAPH_OUT.parent.mkdir(parents=True, exist_ok=True)
                GRAPH_OUT.write_text(graph_output, encoding="utf-8")

            report = load_latest_report()
            snap = snapshot_from_report(report)
            if snap is not None:
                if not history or history[-1].get("run_id") != snap.get("run_id"):
                    history.append(snap)

            clear()
            print(
                render(
                    report,
                    interval=interval,
                    iteration=iteration,
                    observe_ok=(observe_code == 0),
                    graph_ok=(graph_code == 0),
                    history=history,
                )
            )
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\n[ok] loop stopped")


if __name__ == "__main__":
    main()
