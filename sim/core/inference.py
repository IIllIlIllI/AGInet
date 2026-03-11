from __future__ import annotations

from dataclasses import dataclass, field
from math import isfinite


DOMINATION_CAP = 8.0


@dataclass
class Hypothesis:
    hypothesis_id: str
    prior: float
    allowed: bool = True
    notes: list[str] = field(default_factory=list)


@dataclass
class Evidence:
    evidence_id: str
    weight: float
    recency: float
    likelihood_ratio_by_hypothesis: dict[str, float]
    tags: list[str] = field(default_factory=list)


def prior_to_odds(p: float) -> float:
    p = min(max(p, 1e-6), 1 - 1e-6)
    return p / (1 - p)


def odds_to_prob(o: float) -> float:
    if not isfinite(o):
        return 1.0
    return o / (1 + o)


def effective_lr(weight: float, recency: float, raw_lr: float, domination_cap: float = DOMINATION_CAP) -> float:
    return min(weight * recency * raw_lr, domination_cap)


def posterior_for_hypothesis(
    h: Hypothesis,
    evidence_items: list[Evidence],
    missing_penalty: float,
    latent_bonus: float,
    domination_cap: float = DOMINATION_CAP,
) -> float:
    if not h.allowed:
        return 0.0

    odds = prior_to_odds(h.prior)
    for e in evidence_items:
        raw_lr = e.likelihood_ratio_by_hypothesis.get(h.hypothesis_id, 1.0)
        lr = effective_lr(e.weight, e.recency, raw_lr, domination_cap=domination_cap)
        lr = lr * (1 - missing_penalty) * (1 + latent_bonus)
        odds *= max(lr, 1e-6)

    return odds_to_prob(odds)


def compute_posteriors(
    hypotheses: dict[str, Hypothesis],
    evidence_items: list[Evidence],
    missing_penalty: float,
    latent_bonus: float,
    domination_cap: float = DOMINATION_CAP,
) -> dict[str, float]:
    return {
        h.hypothesis_id: posterior_for_hypothesis(
            h,
            evidence_items,
            missing_penalty,
            latent_bonus,
            domination_cap=domination_cap,
        )
        for h in hypotheses.values()
    }


def compute_residual_ambiguity(posteriors: dict[str, float], threshold: float = 0.15) -> int:
    return sum(1 for p in posteriors.values() if p >= threshold)
