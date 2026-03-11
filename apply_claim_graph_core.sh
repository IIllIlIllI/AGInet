#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/claim-graph-core-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] installing AGInet claim graph core"

write_file "$ROOT/sim/core/claim_graph.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass, field


VALID_RELATIONS = {"supports", "contradicts", "elaborates", "speculative", "depends_on"}


@dataclass
class ClaimNode:
    claim_id: str
    text: str
    hypothesis_id: str | None = None
    tags: list[str] = field(default_factory=list)


@dataclass
class ClaimEdge:
    source_claim_id: str
    target_claim_id: str
    relation: str
    weight: float = 1.0

    def __post_init__(self) -> None:
        if self.relation not in VALID_RELATIONS:
            raise ValueError(f"invalid relation: {self.relation}")


@dataclass
class ClaimGraph:
    claims: dict[str, ClaimNode] = field(default_factory=dict)
    edges: list[ClaimEdge] = field(default_factory=list)

    def add_claim(
        self,
        claim_id: str,
        text: str,
        hypothesis_id: str | None = None,
        tags: list[str] | None = None,
    ) -> None:
        self.claims[claim_id] = ClaimNode(
            claim_id=claim_id,
            text=text,
            hypothesis_id=hypothesis_id,
            tags=tags or [],
        )

    def add_edge(
        self,
        source_claim_id: str,
        target_claim_id: str,
        relation: str,
        weight: float = 1.0,
    ) -> None:
        if source_claim_id not in self.claims:
            raise KeyError(f"unknown source claim: {source_claim_id}")
        if target_claim_id not in self.claims:
            raise KeyError(f"unknown target claim: {target_claim_id}")
        self.edges.append(
            ClaimEdge(
                source_claim_id=source_claim_id,
                target_claim_id=target_claim_id,
                relation=relation,
                weight=weight,
            )
        )

    def relation_counts(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for edge in self.edges:
            counts[edge.relation] = counts.get(edge.relation, 0) + 1
        return counts

    def claims_for_hypothesis(self, hypothesis_id: str) -> list[ClaimNode]:
        return [c for c in self.claims.values() if c.hypothesis_id == hypothesis_id]

    def edges_for_claim(self, claim_id: str) -> list[ClaimEdge]:
        return [
            e for e in self.edges
            if e.source_claim_id == claim_id or e.target_claim_id == claim_id
        ]

    def support_score_for_hypothesis(self, hypothesis_id: str) -> float:
        claim_ids = {c.claim_id for c in self.claims_for_hypothesis(hypothesis_id)}
        score = 0.0
        for e in self.edges:
            if e.target_claim_id in claim_ids:
                if e.relation == "supports":
                    score += e.weight
                elif e.relation == "contradicts":
                    score -= e.weight
        return score

    def contradiction_density(self) -> float:
        if not self.edges:
            return 0.0
        contradictions = sum(1 for e in self.edges if e.relation == "contradicts")
        return contradictions / len(self.edges)

    def summary(self) -> dict:
        return {
            "claim_count": len(self.claims),
            "edge_count": len(self.edges),
            "relation_counts": self.relation_counts(),
            "contradiction_density": round(self.contradiction_density(), 4),
        }
EOF

write_file "$ROOT/sim/reference_sim.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass, field

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
    audit: list[str] = field(default_factory=list)


def build_reference_claim_graph() -> ClaimGraph:
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

    return graph


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

    evidence_items = [
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

    missing_penalty = 0.08
    latent_bonus = 0.03

    apply_constraints(hypotheses, constraints, audit)
    posteriors = compute_posteriors(hypotheses, evidence_items, missing_penalty, latent_bonus)
    fragility = compute_fragility(hypotheses, evidence_items, missing_penalty, latent_bonus)
    residual_ambiguity = compute_residual_ambiguity(posteriors)
    sovereignty = compute_sovereignty_report(evidence_items, posteriors, fragility)

    claim_graph = build_reference_claim_graph()
    graph_summary = claim_graph.summary()
    graph_support = {
        hid: round(claim_graph.support_score_for_hypothesis(hid), 4)
        for hid in hypotheses.keys()
    }

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
        audit=audit,
    )


def main() -> None:
    result = run_reference_sim()

    print("=== AGINET REFERENCE SIM ===")
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

echo
echo "[patch] done"
echo "Next steps:"
echo "  python -B -m sim.reference_sim"
echo "  git add sim/core/claim_graph.py sim/reference_sim.py"
echo '  git commit -m "add AGInet claim graph core"'
echo "  git push"
