from __future__ import annotations

import json
import os
import sys
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"
RUN_DIR = ROOT / "sim" / "data" / "run_reports"

RESET = "\033[0m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"


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


def build_state(report: dict) -> dict:
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

    return {
        "sovereignty": sovereignty,
        "contamination": contamination,
        "ambiguity": ambiguity,
        "contradiction_density": contradiction_density,
        "flip": flip,
        "s_state": s_state,
        "c_state": c_state,
        "a_state": a_state,
        "d_state": d_state,
        "f_state": f_state,
    }


def compact_output(report: dict) -> None:
    result = report.get("result", {})
    state = build_state(report)

    status_line = "status: " + " ".join([
        f"{glyph('S', state['s_state'])}={state['sovereignty']:.2f}",
        f"{glyph('C', state['c_state'])}={'1' if state['contamination'] else '0'}",
        f"{glyph('A', state['a_state'])}={state['ambiguity']}",
        f"{glyph('D', state['d_state'])}={state['contradiction_density']:.2f}",
        f"{glyph('F', state['f_state'])}={'1' if state['flip'] else '0'}",
    ])

    print(status_line)
    print(f"run_id: {report.get('run_id')}")
    print(f"graph_variant: {result.get('graph_variant')}")


def full_output(report: dict) -> None:
    result = report.get("result", {})
    posteriors = result.get("posterior_by_hypothesis", {})
    top_id, top_score = top_hypothesis(posteriors)
    graph_summary = result.get("claim_graph_summary", {})
    support = result.get("claim_graph_support", {})
    state = build_state(report)

    compact_output(report)
    print("")
    print(f"timestamp_utc:         {report.get('timestamp_utc')}")
    print(f"top_hypothesis:        {colorize(str(top_id), CYAN)}")
    print(f"top_score:             {top_score:.4f}")
    print(f"residual_ambiguity:    {state['ambiguity']}")
    print(f"sovereignty_pressure:  {state['sovereignty']:.4f}")
    print(f"contamination_flag:    {state['contamination']}")
    print(f"claim_count:           {graph_summary.get('claim_count')}")
    print(f"edge_count:            {graph_summary.get('edge_count')}")
    print(f"contradiction_density: {state['contradiction_density']:.4f}")
    print(f"flip_detected:         {state['flip']}")

    if support:
        print("\nSupport by hypothesis:")
        for hid in sorted(support.keys()):
            score = support[hid]
            if isinstance(score, float):
                print(f"  {hid}: {score:.4f}")
            else:
                print(f"  {hid}: {score}")


def main() -> None:
    report = load_json(LATEST_REPORT)
    if report is None:
        print("AGInet status: no latest report found")
        print(f"expected: {LATEST_REPORT}")
        return

    full = "--full" in sys.argv[1:]
    if full:
        full_output(report)
    else:
        compact_output(report)


if __name__ == "__main__":
    main()
