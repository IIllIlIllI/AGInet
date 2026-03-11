from __future__ import annotations

import json
import os
import time
from datetime import datetime, UTC
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"


def clear() -> None:
    os.system("clear")


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


def render(report: dict | None, interval: float) -> str:
    now = datetime.now(UTC).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines: list[str] = []
    lines.append("=== AGINET WATCH ===")
    lines.append(f"time: {now}")
    lines.append(f"refresh_interval_sec: {interval}")
    lines.append("press Ctrl+C to stop")
    lines.append("")

    if report is None:
        lines.append("No latest report found.")
        lines.append(f"Expected file: {LATEST_REPORT}")
        lines.append("")
        lines.append("Tip:")
        lines.append("  tools/bin/agi observe")
        return "\n".join(lines)

    result = report.get("result", {})
    posteriors = result.get("posterior_by_hypothesis", {})
    top_id, top_score = top_hypothesis(posteriors)
    graph_summary = result.get("claim_graph_summary", {})
    support = result.get("claim_graph_support", {})

    lines.append(f"run_id:                {report.get('run_id')}")
    lines.append(f"timestamp_utc:         {report.get('timestamp_utc')}")
    lines.append(f"graph_variant:         {result.get('graph_variant')}")
    lines.append(f"top_hypothesis:        {top_id}")
    lines.append(f"top_score:             {top_score:.4f}")
    lines.append(f"residual_ambiguity:    {result.get('residual_ambiguity')}")
    lines.append(f"sovereignty_pressure:  {float(result.get('sovereignty_pressure', 0.0)):.4f}")
    lines.append(f"contamination_flag:    {result.get('contamination_flag')}")
    lines.append(f"claim_count:           {graph_summary.get('claim_count')}")
    lines.append(f"edge_count:            {graph_summary.get('edge_count')}")
    lines.append(f"contradiction_density: {graph_summary.get('contradiction_density')}")
    lines.append(f"relation_counts:       {graph_summary.get('relation_counts')}")
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

    audit = result.get("audit", [])
    if audit:
        lines.append("Recent audit lines:")
        for line in audit[-6:]:
            lines.append(f"  {line}")

    return "\n".join(lines)


def main() -> None:
    interval = float(os.environ.get("AGINET_WATCH_INTERVAL", "3"))
    try:
        while True:
            report = load_latest_report()
            clear()
            print(render(report, interval))
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\n[ok] watch stopped")


if __name__ == "__main__":
    main()
