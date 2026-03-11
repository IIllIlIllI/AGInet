from __future__ import annotations

import json
from pathlib import Path


ROOT = Path.cwd()
RUN_DIR = ROOT / "sim" / "data" / "run_reports"


def load_reports() -> list[dict]:
    if not RUN_DIR.exists():
        return []
    out = []
    for p in sorted(RUN_DIR.glob("run-*.json")):
        try:
            out.append(json.loads(p.read_text(encoding="utf-8")))
        except Exception:
            pass
    return out


def top_hypothesis(report: dict) -> tuple[str | None, float]:
    post = report.get("result", {}).get("posterior_by_hypothesis", {})
    if not post:
        return None, 0.0
    hid = max(post, key=post.get)
    return hid, float(post[hid])


def main() -> None:
    reports = load_reports()
    print("=== AGINET DRIFT REPORT ===")
    if len(reports) < 2:
        print("Not enough runs for drift analysis.")
        print(f"Runs available: {len(reports)}")
        return

    a = reports[-2]
    b = reports[-1]

    a_top, a_score = top_hypothesis(a)
    b_top, b_score = top_hypothesis(b)

    a_result = a.get("result", {})
    b_result = b.get("result", {})

    print(f"previous_run: {a['run_id']}")
    print(f"latest_run:   {b['run_id']}")
    print("")
    print(f"top_hypothesis: {a_top} -> {b_top}")
    print(f"top_score:      {a_score:.4f} -> {b_score:.4f}")
    print(
        f"residual_ambiguity: "
        f"{a_result.get('residual_ambiguity')} -> {b_result.get('residual_ambiguity')}"
    )
    print(
        f"sovereignty_pressure: "
        f"{a_result.get('sovereignty_pressure'):.4f} -> {b_result.get('sovereignty_pressure'):.4f}"
    )
    print(
        f"contamination_flag: "
        f"{a_result.get('contamination_flag')} -> {b_result.get('contamination_flag')}"
    )
    print(
        f"claim_graph_contradiction_density: "
        f"{a_result.get('claim_graph_summary', {}).get('contradiction_density')} -> "
        f"{b_result.get('claim_graph_summary', {}).get('contradiction_density')}"
    )


if __name__ == "__main__":
    main()
