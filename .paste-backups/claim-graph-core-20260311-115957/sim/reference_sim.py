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
