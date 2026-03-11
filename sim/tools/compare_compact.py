from __future__ import annotations

import json
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"
TARGETS = ["h_verified", "h_brigaded", "h_uncertain"]


def load_latest_report() -> dict | None:
    if not LATEST_REPORT.exists():
        return None
    try:
        return json.loads(LATEST_REPORT.read_text(encoding="utf-8"))
    except Exception:
        return None


def rank_map(posteriors: dict[str, float]) -> dict[str, int]:
    ranked = sorted(posteriors.items(), key=lambda kv: kv[1], reverse=True)
    return {hid: idx for idx, (hid, _) in enumerate(ranked, start=1)}


def main() -> None:
    report = load_latest_report()

    print("=== AGINET COMPARE (COMPACT) ===")

    if report is None:
        print("No latest report found.")
        print(f"Expected file: {LATEST_REPORT}")
        return

    result = report.get("result", {})
    posteriors = result.get("posterior_by_hypothesis", {})
    support = result.get("claim_graph_support", {})
    fragility = result.get("fragility_by_hypothesis", {})
    ambiguity = result.get("residual_ambiguity")
    sovereignty = float(result.get("sovereignty_pressure", 0.0))
    contamination = bool(result.get("contamination_flag"))
    variant = result.get("graph_variant")

    ranks = rank_map(posteriors)

    print(f"run_id:              {report.get('run_id')}")
    print(f"graph_variant:       {variant}")
    print(f"residual_ambiguity:  {ambiguity}")
    print(f"sovereignty:         {sovereignty:.4f}")
    print(f"contamination:       {contamination}")
    print("")
    print("hypothesis      rank  posterior  support   max_fragility  strongest_evidence")
    print("--------------------------------------------------------------------------")

    for hid in TARGETS:
        posterior = float(posteriors.get(hid, 0.0))
        support_score = float(support.get(hid, 0.0))
        frag = fragility.get(hid, {})
        if frag:
            strongest_evidence, strongest_value = max(frag.items(), key=lambda kv: kv[1])
        else:
            strongest_evidence, strongest_value = "-", 0.0

        print(
            f"{hid:<15} "
            f"{str(ranks.get(hid, '-')):<5} "
            f"{posterior:<10.4f} "
            f"{support_score:<8.4f} "
            f"{strongest_value:<13.4f} "
            f"{strongest_evidence}"
        )


if __name__ == "__main__":
    main()
