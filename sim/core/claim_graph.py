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
