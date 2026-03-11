from __future__ import annotations

import json
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"


def load_latest_report() -> dict | None:
    if not LATEST_REPORT.exists():
        return None
    try:
        return json.loads(LATEST_REPORT.read_text(encoding="utf-8"))
    except Exception:
        return None


def top_hypothesis(posteriors: dict[str, float]) -> tuple[str | None, float]:
    if not posteriors:
        return None, 0.0
    hid = max(posteriors, key=posteriors.get)
    return hid, float(posteriors[hid])


def sorted_posteriors(posteriors: dict[str, float]) -> list[tuple[str, float]]:
    return sorted(posteriors.items(), key=lambda kv: kv[1], reverse=True)


def main() -> None:
    report = load_latest_report()

    print("=== AGINET EXPLAIN ===")

    if report is None:
        print("No latest report found.")
        print(f"Expected file: {LATEST_REPORT}")
        return

    result = report.get("result", {})
    run_id = report.get("run_id")
    variant = result.get("graph_variant")
    posteriors = result.get("posterior_by_hypothesis", {})
    support = result.get("claim_graph_support", {})
    fragility = result.get("fragility_by_hypothesis", {})
    ambiguity = result.get("residual_ambiguity")
    sovereignty = float(result.get("sovereignty_pressure", 0.0))
    contamination = bool(result.get("contamination_flag"))
    audit = result.get("audit", [])

    winner, winner_score = top_hypothesis(posteriors)
    ranked = sorted_posteriors(posteriors)

    print(f"run_id:          {run_id}")
    print(f"graph_variant:   {variant}")
    print(f"winner:          {winner}")
    print(f"winner_score:    {winner_score:.4f}")
    print("")

    if ranked:
        print("Posterior ranking:")
        for hid, score in ranked:
            print(f"  {hid}: {score:.4f}")
        print("")

    print("Why it won:")
    if winner is None:
        print("  No winner could be determined.")
    else:
        top_support = support.get(winner, 0.0)
        print(f"  - {winner} has the highest posterior probability in the latest run.")
        print(f"  - Graph support score for {winner}: {top_support:.4f}")

        if len(ranked) > 1:
            runner_up, runner_score = ranked[1]
            margin = winner_score - runner_score
            print(f"  - Margin over runner-up ({runner_up}): {margin:.4f}")

        winner_fragility = fragility.get(winner, {})
        if winner_fragility:
            strongest = max(winner_fragility.items(), key=lambda kv: kv[1])
            print(
                f"  - Most load-bearing evidence for {winner}: "
                f"{strongest[0]} (fragility {strongest[1]:.4f})"
            )

    print("")
    print("System conditions:")
    print(f"  - Residual ambiguity: {ambiguity}")
    print(f"  - Sovereignty pressure: {sovereignty:.4f}")
    print(f"  - Contamination flag: {contamination}")

    if ambiguity is not None:
        if int(ambiguity) >= 3:
            print("  - Multiple live hypotheses remain unresolved.")
        elif int(ambiguity) == 2:
            print("  - Narrow uncertainty remains.")
        else:
            print("  - Hypothesis space is relatively resolved.")

    if sovereignty >= 0.62:
        print("  - High sovereignty pressure: explanation should be treated cautiously.")
    elif sovereignty >= 0.35:
        print("  - Moderate sovereignty pressure: watch for manipulation or brittle reasoning.")
    else:
        print("  - Low sovereignty pressure: current reasoning conditions look relatively stable.")

    print("")
    print("Support by hypothesis:")
    if support:
        for hid in sorted(support.keys()):
            print(f"  {hid}: {support[hid]:.4f}")
    else:
        print("  No graph support data available.")

    print("")
    print("Relevant audit notes:")
    matched = [
        line for line in audit
        if "sovereignty_note" in line
        or "ambiguity" in line
        or "claim_graph" in line
        or "contamination" in line
    ]
    if matched:
        for line in matched[-8:]:
            print(f"  {line}")
    else:
        print("  No audit notes found.")

    print("")
    print("Bottom line:")
    if winner is None:
        print("  The system does not currently have a usable explanation.")
    else:
        print(
            f"  {winner} is leading because it currently has the strongest combined "
            "posterior standing in the latest run."
        )
        if ambiguity is not None and int(ambiguity) >= 2:
            print(
                "  However, the result is not fully settled because multiple hypotheses "
                "still remain live."
            )
        if sovereignty >= 0.35:
            print(
                "  Confidence should also be tempered by sovereignty pressure and "
                "fragility indicators."
            )


if __name__ == "__main__":
    main()
