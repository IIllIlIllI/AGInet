#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/reference-sim-split-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] splitting reference sim into AGInet core modules"

write_file "$ROOT/sim/core/inference.py" <<'EOF'
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
EOF

write_file "$ROOT/sim/core/constraints.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from sim.core.inference import Hypothesis


@dataclass
class Constraint:
    constraint_id: str
    description: str
    fn: Callable[[Hypothesis], bool]


def apply_constraints(
    hypotheses: dict[str, Hypothesis],
    constraints: list[Constraint],
    audit: list[str] | None = None,
) -> None:
    for h in hypotheses.values():
        for c in constraints:
            if not c.fn(h):
                h.allowed = False
                h.notes.append(f"violated constraint: {c.constraint_id}")
                if audit is not None:
                    audit.append(f"[constraint] {h.hypothesis_id} invalidated by {c.constraint_id}")
                break
EOF

write_file "$ROOT/sim/core/fragility.py" <<'EOF'
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
EOF

write_file "$ROOT/sim/core/sovereignty.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass

from sim.core.fragility import max_fragility
from sim.core.inference import Evidence, compute_residual_ambiguity


DEFAULT_CONTAMINATION_THRESHOLD = 0.62


@dataclass
class SovereigntyReport:
    pressure: float
    contamination_flag: bool
    anomaly_pressure: float
    concentration_pressure: float
    ambiguity_pressure: float
    notes: list[str]


def compute_sovereignty_report(
    evidence_items: list[Evidence],
    posteriors: dict[str, float],
    fragility: dict[str, dict[str, float]],
    threshold: float = DEFAULT_CONTAMINATION_THRESHOLD,
) -> SovereigntyReport:
    coercive_tags = {"propaganda", "dog_whistle", "brigade", "manipulative"}
    anomaly_pressure = sum(
        0.12 for e in evidence_items if any(tag in coercive_tags for tag in e.tags)
    )

    peak_fragility = max_fragility(fragility)
    concentration_pressure = 0.18 if peak_fragility > 0.25 else 0.0
    ambiguity_pressure = 0.10 if compute_residual_ambiguity(posteriors, threshold=0.20) > 1 else 0.0

    pressure = min(anomaly_pressure + concentration_pressure + ambiguity_pressure, 1.0)
    contamination_flag = pressure > threshold

    notes: list[str] = []
    if anomaly_pressure > 0:
        notes.append("coercive or manipulative tag pressure detected")
    if concentration_pressure > 0:
        notes.append("fragility concentration indicates brittle reasoning")
    if ambiguity_pressure > 0:
        notes.append("multiple live hypotheses remain unresolved")
    if contamination_flag:
        notes.append("pressure exceeded contamination threshold")

    return SovereigntyReport(
        pressure=pressure,
        contamination_flag=contamination_flag,
        anomaly_pressure=anomaly_pressure,
        concentration_pressure=concentration_pressure,
        ambiguity_pressure=ambiguity_pressure,
        notes=notes,
    )
EOF

write_file "$ROOT/sim/reference_sim.py" <<'EOF'
from __future__ import annotations

from dataclasses import dataclass, field

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
    audit: list[str] = field(default_factory=list)


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

    audit.append(f"[posterior] {posteriors}")
    audit.append(f"[ambiguity] residual={residual_ambiguity}")
    audit.append(f"[sovereignty] pressure={sovereignty.pressure:.3f}")
    audit.append(f"[contamination] flag={sovereignty.contamination_flag}")
    for note in sovereignty.notes:
        audit.append(f"[sovereignty_note] {note}")

    return SimResult(
        posterior_by_hypothesis=posteriors,
        fragility_by_hypothesis=fragility,
        residual_ambiguity=residual_ambiguity,
        sovereignty_pressure=sovereignty.pressure,
        contamination_flag=sovereignty.contamination_flag,
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
echo "  git add sim/core sim/reference_sim.py"
echo '  git commit -m "split reference sim into core AGInet modules"'
echo "  git push"
