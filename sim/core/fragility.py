from __future__ import annotations

from sim.core.inference import Hypothesis, Evidence, compute_posteriors


def compute_fragility(
    hypotheses: dict[str, Hypothesis],
    evidence_items: list[Evidence],
    missing_penalty: float,
    latent_bonus: float,
) -> dict[str, dict[str, float]]:
    baseline = compute_posteriors(hypotheses, evidence_items, missing_penalty, latent_bonus)
    out: dict[str, dict[str, float]] = {}

    for h in hypotheses.values():
        by_evidence: dict[str, float] = {}
        for i, e in enumerate(evidence_items):
            reduced = evidence_items[:i] + evidence_items[i + 1 :]
            reduced_post = compute_posteriors(hypotheses, reduced, missing_penalty, latent_bonus)
            by_evidence[e.evidence_id] = abs(
                baseline[h.hypothesis_id] - reduced_post[h.hypothesis_id]
            )
        out[h.hypothesis_id] = by_evidence

    return out


def max_fragility(fragility: dict[str, dict[str, float]]) -> float:
    values = [
        delta
        for evidence_map in fragility.values()
        for delta in evidence_map.values()
    ]
    return max(values) if values else 0.0
