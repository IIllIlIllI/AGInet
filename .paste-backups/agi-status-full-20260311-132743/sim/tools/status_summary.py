from __future__ import annotations

import json
import os
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"
RUN_DIR = ROOT / "sim" / "data" / "run_reports"

RESET = "\033[0m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"


def use_color() -> bool:
    return os.environ.get("AGINET_NO_COLOR", "0") != "1"


def colorize(text: str, color: str) -> str:
    if not use_color():
        return text
    return f"{color}{text}{RESET}"


def glyph(label: str, state: str) -> str:
    palette = {
        "green": GREEN,
        "yellow": YELLOW,
        "red": RED,
    }
    return colorize(label, palette.get(state, ""))


def load_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def latest_two_reports() -> list[dict]:
    if not RUN_DIR.exists():
        return []
    reports = []
    for p in sorted(RUN_DIR.glob("run-*.json")):
        obj = load_json(p)
        if obj is not None:
            reports.append(obj)
    return reports[-2:]


def top_hypothesis(posteriors: dict) -> tuple[str | None, float]:
    if not posteriors:
        return None, 0.0
    hid = max(posteriors, key=posteriors.get)
    return hid, float(posteriors[hid])


def main() -> None:
    report = load_json(LATEST_REPORT)
    if report is None:
        print("AGInet status: no latest report found")
        print(f"expected: {LATEST_REPORT}")
        return

    result = report.get("result", {})
    sovereignty = float(result.get("sovereignty_pressure", 0.0))
    contamination = bool(result.get("contamination_flag"))
    ambiguity = int(result.get("residual_ambiguity", 0) or 0)

    graph_summary = result.get("claim_graph_summary", {})
    contradiction_density = float(graph_summary.get("contradiction_density", 0.0) or 0.0)

    recent = latest_two_reports()
    flip = False
    if len(recent) == 2:
        a = recent[0].get("result", {}).get("posterior_by_hypothesis", {})
        b = recent[1].get("result", {}).get("posterior_by_hypothesis", {})
        a_top, _ = top_hypothesis(a)
        b_top, _ = top_hypothesis(b)
        flip = a_top != b_top

    s_state = "red" if sovereignty >= 0.62 else "yellow" if sovereignty >= 0.35 else "green"
    c_state = "red" if contamination else "green"
    a_state = "red" if ambiguity >= 3 else "yellow" if ambiguity >= 2 else "green"
    d_state = "red" if contradiction_density >= 0.30 else "yellow" if contradiction_density >= 0.15 else "green"
    f_state = "red" if flip else "green"

    status_line = "status: " + " ".join([
        f"{glyph('S', s_state)}={sovereignty:.2f}",
        f"{glyph('C', c_state)}={'1' if contamination else '0'}",
        f"{glyph('A', a_state)}={ambiguity}",
        f"{glyph('D', d_state)}={contradiction_density:.2f}",
        f"{glyph('F', f_state)}={'1' if flip else '0'}",
    ])

    print(status_line)
    print(f"run_id: {report.get('run_id')}")
    print(f"graph_variant: {result.get('graph_variant')}")


if __name__ == "__main__":
    main()
