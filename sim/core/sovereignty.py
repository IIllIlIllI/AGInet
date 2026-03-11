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
