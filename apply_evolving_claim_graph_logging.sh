#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/evolving-claim-graph-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "${file#"$ROOT/"}")"
    cp "$file" "$BACKUP_DIR/${file#"$ROOT/"}"
    echo "[backup] ${file#"$ROOT/"}"
  fi
}

write_file() {
  local file="$1"
  backup_file "$file"
  mkdir -p "$(dirname "$file")"
  cat > "$file"
  echo "[write] ${file#"$ROOT/"}"
}

echo "[patch] installing evolving claim graph logging"

write_file "$ROOT/sim/reference_sim.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, UTC

from sim.core.claim_graph import ClaimGraph
from sim.core.constraints import Constraint, apply_constraints
from sim.core.fragility import compute_fragility
from sim.core.inference import Evidence, Hypothesis, compute_posteriors, compute_residual_ambiguity
from sim.core.sovereignty import compute_sovereignty_report


@dataclass
class SimResult:
    posterior_by_hypothesis: dict[str, float]
    fragility_by_hypothesis: dict[str, dict[str, float]]
    residual_ambiguity: int
    sovereignty_pressure: float
    contamination_flag: bool
    claim_graph_summary: dict
    claim_graph_support: dict[str, float]
    graph_variant: str
    audit: list[str] = field(default_factory=list)


def current_variant_key() -> int:
    # Stable, observable variation by current UTC minute bucket.
    now = datetime.now(UTC)
    return now.minute % 3


def build_reference_claim_graph(variant: int | None = None) -> tuple[ClaimGraph, str]:
    if variant is None:
        variant = current_variant_key()

    graph = ClaimGraph()

    graph.add_claim(
        "c_dataset_verified",
        "A dataset-backed signal supports the verified interpretation.",
        hypothesis_id="h_verified",
        tags=["verified", "dataset"],
    )
    graph.add_claim(
        "c_forum_burst",
        "A forum burst suggests coordinated or brigaded amplification.",
        hypothesis_id="h_brigaded",
        tags=["forum", "brigade"],
    )
    graph.add_claim(
        "c_blog_analysis",
        "A derivative analysis blog offers mixed support and interpretation.",
        hypothesis_id="h_uncertain",
        tags=["derivative"],
    )
    graph.add_claim(
        "c_verified_vs_brigaded",
        "Verified and brigaded interpretations are in tension.",
        tags=["meta"],
    )

    graph.add_edge("c_dataset_verified", "c_verified_vs_brigaded", "supports", weight=0.9)
    graph.add_edge("c_forum_burst", "c_verified_vs_brigaded", "supports", weight=0.8)
    graph.add_edge("c_dataset_verified", "c_forum_burst", "contradicts", weight=0.7)
    graph.add_edge("c_blog_analysis", "c_dataset_verified", "elaborates", weight=0.4)
    graph.add_edge("c_blog_analysis", "c_forum_burst", "speculative", weight=0.3)

    variant_name = "baseline"

    if variant == 1:
        variant_name = "heightened_brigade"
        graph.add_claim(
            "c_social_echo",
            "A social echo chamber reinforces brigaded interpretation.",
            hypothesis_id="h_brigaded",
            tags=["social", "echo"],
        )
        graph.add_edge("c_social_echo", "c_forum_burst", "supports", weight=0.7)
        graph.add_edge("c_social_echo", "c_dataset_verified", "contradicts", weight=0.5)

    elif variant == 2:
        variant_name = "verification_reinforced"
        graph.add_claim(
            "c_secondary_verification",
            "A secondary verification source reinforces the verified interpretation.",
            hypothesis_id="h_verified",
            tags=["verified", "secondary"],
        )
        graph.add_edge("c_secondary_verification", "c_dataset_verified", "supports", weight=0.8)
        graph.add_edge("c_secondary_verification", "c_verified_vs_brigaded", "supports", weight=0.6)

    return graph, variant_name


def build_evidence_items(variant_name: str) -> list[Evidence]:
    items = [
        Evidence(
            "e_dataset",
            weight=1.0,
            recency=0.95,
            likelihood_ratio_by_hypothesis={
                "h_verified": 3.4,
                "h_brigaded": 0.7,
                "h_uncertain": 1.2,
            },
            tags=["verified"],
        ),
        Evidence(
            "e_forum_burst",
            weight=0.8,
            recency=1.0,
            likelihood_ratio_by_hypothesis={
                "h_verified": 0.9,
                "h_brigaded": 2.9,
                "h_uncertain": 1.4,
            },
            tags=["brigade", "propaganda"],
        ),
        Evidence(
            "e_analysis_blog",
            weight=0.6,
            recency=0.85,
            likelihood_ratio_by_hypothesis={
                "h_verified": 1.7,
                "h_brigaded": 1.2,
                "h_uncertain": 1.5,
            },
            tags=["derivative"],
        ),
    ]

    if variant_name == "heightened_brigade":
        items.append(
            Evidence(
                "e_social_echo",
                weight=0.7,
                recency=1.0,
                likelihood_ratio_by_hypothesis={
                    "h_verified": 0.8,
                    "h_brigaded": 2.2,
                    "h_uncertain": 1.1,
                },
                tags=["brigade", "social"],
            )
        )
    elif variant_name == "verification_reinforced":
        items.append(
            Evidence(
                "e_secondary_verification",
                weight=0.9,
                recency=0.92,
                likelihood_ratio_by_hypothesis={
                    "h_verified": 2.4,
                    "h_brigaded": 0.8,
                    "h_uncertain": 1.0,
                },
                tags=["verified", "secondary"],
            )
        )

    return items


def run_reference_sim() -> SimResult:
    audit: list[str] = []

    hypotheses = {
        "h_verified": Hypothesis("h_verified", prior=0.45),
        "h_brigaded": Hypothesis("h_brigaded", prior=0.30),
        "h_uncertain": Hypothesis("h_uncertain", prior=0.25),
    }

    constraints = [
        Constraint(
            "no_impossible_verified_state",
            "Verified state cannot be marked impossible.",
            lambda h: not (h.hypothesis_id == "h_verified" and "impossible" in h.notes),
        )
    ]

    claim_graph, variant_name = build_reference_claim_graph()
    evidence_items = build_evidence_items(variant_name)

    missing_penalty = 0.08
    latent_bonus = 0.03

    apply_constraints(hypotheses, constraints, audit)
    posteriors = compute_posteriors(hypotheses, evidence_items, missing_penalty, latent_bonus)
    fragility = compute_fragility(hypotheses, evidence_items, missing_penalty, latent_bonus)
    residual_ambiguity = compute_residual_ambiguity(posteriors)
    sovereignty = compute_sovereignty_report(evidence_items, posteriors, fragility)

    graph_summary = claim_graph.summary()
    graph_support = {
        hid: round(claim_graph.support_score_for_hypothesis(hid), 4)
        for hid in hypotheses.keys()
    }

    audit.append(f"[variant] {variant_name}")
    audit.append(f"[posterior] {posteriors}")
    audit.append(f"[ambiguity] residual={residual_ambiguity}")
    audit.append(f"[sovereignty] pressure={sovereignty.pressure:.3f}")
    audit.append(f"[contamination] flag={sovereignty.contamination_flag}")
    audit.append(f"[claim_graph] summary={graph_summary}")
    audit.append(f"[claim_graph] support={graph_support}")
    for note in sovereignty.notes:
        audit.append(f"[sovereignty_note] {note}")

    return SimResult(
        posterior_by_hypothesis=posteriors,
        fragility_by_hypothesis=fragility,
        residual_ambiguity=residual_ambiguity,
        sovereignty_pressure=sovereignty.pressure,
        contamination_flag=sovereignty.contamination_flag,
        claim_graph_summary=graph_summary,
        claim_graph_support=graph_support,
        graph_variant=variant_name,
        audit=audit,
    )


def main() -> None:
    result = run_reference_sim()

    print("=== AGINET REFERENCE SIM ===")
    print(f"\nGraph variant:\n  {result.graph_variant}")

    print("\nPosteriors:")
    for hid, p in sorted(result.posterior_by_hypothesis.items()):
        print(f"  {hid}: {p:.4f}")

    print("\nFragility:")
    for hid, values in sorted(result.fragility_by_hypothesis.items()):
        print(f"  {hid}:")
        for eid, delta in sorted(values.items()):
            print(f"    {eid}: {delta:.4f}")

    print("\nResidual ambiguity:")
    print(f"  {result.residual_ambiguity}")

    print("\nSovereignty pressure:")
    print(f"  {result.sovereignty_pressure:.4f}")

    print("\nContamination flag:")
    print(f"  {result.contamination_flag}")

    print("\nClaim graph summary:")
    for k, v in result.claim_graph_summary.items():
        print(f"  {k}: {v}")

    print("\nClaim graph support by hypothesis:")
    for hid, score in sorted(result.claim_graph_support.items()):
        print(f"  {hid}: {score:.4f}")

    print("\nAudit trail:")
    for line in result.audit:
        print(f"  {line}")


if __name__ == "__main__":
    main()
EOF

write_file "$ROOT/sim/observatory/drift_report.py" <<'EOF'
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


def safe_get_graph_summary(report: dict) -> dict:
    return report.get("result", {}).get("claim_graph_summary", {})


def safe_get_graph_support(report: dict) -> dict:
    return report.get("result", {}).get("claim_graph_support", {})


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

    a_graph = safe_get_graph_summary(a)
    b_graph = safe_get_graph_summary(b)

    print(f"previous_run: {a['run_id']}")
    print(f"latest_run:   {b['run_id']}")
    print("")
    print(f"graph_variant: {a_result.get('graph_variant')} -> {b_result.get('graph_variant')}")
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
        f"claim_count: {a_graph.get('claim_count')} -> {b_graph.get('claim_count')}"
    )
    print(
        f"edge_count:  {a_graph.get('edge_count')} -> {b_graph.get('edge_count')}"
    )
    print(
        "contradiction_density: "
        f"{a_graph.get('contradiction_density')} -> {b_graph.get('contradiction_density')}"
    )
    print(
        f"relation_counts: {a_graph.get('relation_counts')} -> {b_graph.get('relation_counts')}"
    )

    print("\nSupport by hypothesis:")
    a_support = safe_get_graph_support(a)
    b_support = safe_get_graph_support(b)
    all_h = sorted(set(a_support.keys()) | set(b_support.keys()))
    for hid in all_h:
        print(f"  {hid}: {a_support.get(hid)} -> {b_support.get(hid)}")


if __name__ == "__main__":
    main()
EOF

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  tools/bin/agi observe"
echo "  sleep 65"
echo "  tools/bin/agi observe"
echo "  tools/bin/agi drift"
echo
echo "Suggested commit:"
echo '  git add sim/reference_sim.py sim/observatory/drift_report.py'
echo '  git commit -m "log evolving claim graphs in AGInet observability"'
echo "  git push"
