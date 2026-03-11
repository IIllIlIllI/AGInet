#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/reference-sim-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] installing AGInet reference sim engine"

write_file "$ROOT/sim/reference_sim.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass, field
from math import isfinite
from typing import Callable


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


@dataclass
class Constraint:
    constraint_id: str
    description: str
    fn: Callable[[Hypothesis], bool]


@dataclass
class SimResult:
    posterior_by_hypothesis: dict[str, float]
    fragility_by_hypothesis: dict[str, dict[str, float]]
    residual_ambiguity: int
    sovereignty_pressure: float
    contamination_flag: bool
    audit: list[str]


DOMINATION_CAP = 8.0
CONTAMINATION_THRESHOLD = 0.62


def prior_to_odds(p: float) -> float:
    p = min(max(p, 1e-6), 1 - 1e-6)
    return p / (1 - p)


def odds_to_prob(o: float) -> float:
    if not isfinite(o):
        return 1.0
    return o / (1 + o)


def apply_constraints(
    hypotheses: dict[str, Hypothesis],
    constraints: list[Constraint],
    audit: list[str],
) -> None:
    for h in hypotheses.values():
        for c in constraints:
            if not c.fn(h):
                h.allowed = False
                h.notes.append(f"violated constraint: {c.constraint_id}")
                audit.append(f"[constraint] {h.hypothesis_id} invalidated by {c.constraint_id}")
                break


def effective_lr(weight: float, recency: float, raw_lr: float) -> float:
    return min(weight * recency * raw_lr, DOMINATION_CAP)


def posterior_for_hypothesis(
    h: Hypothesis,
    evidence_items: list[Evidence],
    missing_penalty: float,
    latent_bonus: float,
) -> float:
    if not h.allowed:
        return 0.0

    odds = prior_to_odds(h.prior)
    for e in evidence_items:
        raw_lr = e.likelihood_ratio_by_hypothesis.get(h.hypothesis_id, 1.0)
        lr = effective_lr(e.weight, e.recency, raw_lr)
        lr = lr * (1 - missing_penalty) * (1 + latent_bonus)
        odds *= max(lr, 1e-6)

    return odds_to_prob(odds)


def compute_posteriors(
    hypotheses: dict[str, Hypothesis],
    evidence_items: list[Evidence],
    missing_penalty: float,
    latent_bonus: float,
) -> dict[str, float]:
    return {
        h.hypothesis_id: posterior_for_hypothesis(h, evidence_items, missing_penalty, latent_bonus)
        for h in hypotheses.values()
    }


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


def compute_residual_ambiguity(posteriors: dict[str, float], threshold: float = 0.15) -> int:
    return sum(1 for p in posteriors.values() if p >= threshold)


def compute_sovereignty_pressure(
    evidence_items: list[Evidence],
    posteriors: dict[str, float],
    fragility: dict[str, dict[str, float]],
) -> float:
    coercive_tags = {"propaganda", "dog_whistle", "brigade", "manipulative"}
    anomaly_pressure = sum(
        0.12 for e in evidence_items if any(tag in coercive_tags for tag in e.tags)
    )

    concentration_pressure = 0.0
    for values in fragility.values():
        if not values:
            continue
        max_fragility = max(values.values())
        if max_fragility > 0.25:
            concentration_pressure += 0.18

    ambiguity_pressure = 0.10 if compute_residual_ambiguity(posteriors, threshold=0.20) > 1 else 0.0
    pressure = anomaly_pressure + concentration_pressure + ambiguity_pressure
    return min(pressure, 1.0)


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
    sovereignty_pressure = compute_sovereignty_pressure(evidence_items, posteriors, fragility)
    contamination_flag = sovereignty_pressure > CONTAMINATION_THRESHOLD

    audit.append(f"[posterior] {posteriors}")
    audit.append(f"[ambiguity] residual={residual_ambiguity}")
    audit.append(f"[sovereignty] pressure={sovereignty_pressure:.3f}")
    audit.append(f"[contamination] flag={contamination_flag}")

    return SimResult(
        posterior_by_hypothesis=posteriors,
        fragility_by_hypothesis=fragility,
        residual_ambiguity=residual_ambiguity,
        sovereignty_pressure=sovereignty_pressure,
        contamination_flag=contamination_flag,
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

    print("\nAudit trail:")
    for line in result.audit:
        print(f"  {line}")


if __name__ == "__main__":
    main()
EOF

echo
echo "[patch] done"
echo "Next steps:"
echo "  python -B sim/reference_sim.py"
echo "  git add sim/reference_sim.py"
echo '  git commit -m "add AGInet reference simulation engine"'
echo "  git push"
