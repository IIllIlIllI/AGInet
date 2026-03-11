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
