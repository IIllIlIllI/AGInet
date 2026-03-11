#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/full-claim-graph-payload-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] saving full claim graph payload into AGInet reports"

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
    claim_graph_payload: dict
    graph_variant: str
    audit: list[str] = field(default_factory=list)


def current_variant_key() -> int:
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


def serialize_claim_graph(graph: ClaimGraph, hypothesis_ids: list[str]) -> dict:
    return {
        "claims": [
            {
                "claim_id": claim.claim_id,
                "text": claim.text,
                "hypothesis_id": claim.hypothesis_id,
                "tags": claim.tags,
            }
            for claim in graph.claims.values()
        ],
        "edges": [
            {
                "source_claim_id": edge.source_claim_id,
                "target_claim_id": edge.target_claim_id,
                "relation": edge.relation,
                "weight": edge.weight,
            }
            for edge in graph.edges
        ],
        "summary": graph.summary(),
        "support_by_hypothesis": {
            hid: round(graph.support_score_for_hypothesis(hid), 4)
            for hid in hypothesis_ids
        },
    }


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
    graph_payload = serialize_claim_graph(claim_graph, list(hypotheses.keys()))

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
        claim_graph_payload=graph_payload,
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

write_file "$ROOT/sim/observatory/run_logger.py" <<'EOF'
from __future__ import annotations

import json
from dataclasses import asdict, is_dataclass
from datetime import datetime, UTC
from pathlib import Path

from sim.reference_sim import run_reference_sim


ROOT = Path.cwd()
DATA_DIR = ROOT / "sim" / "data"
RUN_DIR = DATA_DIR / "run_reports"
LATEST_PATH = DATA_DIR / "latest_report.json"


def normalize(obj):
    if is_dataclass(obj):
        return asdict(obj)
    if isinstance(obj, dict):
        return {k: normalize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [normalize(v) for v in obj]
    return obj


def build_report() -> dict:
    result = run_reference_sim()
    ts = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    payload = {
        "run_id": f"run-{ts}",
        "timestamp_utc": ts,
        "result": normalize(result),
    }
    return payload


def save_report(report: dict) -> Path:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    out = RUN_DIR / f"{report['run_id']}.json"
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    LATEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    LATEST_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return out


def main() -> None:
    report = build_report()
    out = save_report(report)
    print(f"[ok] saved run report: {out}")
    print(f"[ok] updated latest report: {LATEST_PATH}")
    graph_payload = report.get("result", {}).get("claim_graph_payload", {})
    print(f"[ok] graph claims saved: {len(graph_payload.get('claims', []))}")
    print(f"[ok] graph edges saved: {len(graph_payload.get('edges', []))}")


if __name__ == "__main__":
    main()
EOF

write_file "$ROOT/sim/tools/claim_graph_visualizer.py" <<'EOF'
from __future__ import annotations

import json
from pathlib import Path

from sim.reference_sim import build_reference_claim_graph


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"

RELATION_ARROW = {
    "supports": "-->",
    "contradicts": "-.->",
    "elaborates": "-->",
    "speculative": "-.->",
    "depends_on": "-->",
}


def sanitize(node_id: str) -> str:
    return node_id.replace("-", "_").replace(" ", "_")


def relation_label(relation: str, weight: float) -> str:
    return f"{relation} ({weight:.1f})"


def try_load_latest_report() -> dict | None:
    if not LATEST_REPORT.exists():
        return None
    try:
        return json.loads(LATEST_REPORT.read_text(encoding="utf-8"))
    except Exception:
        return None


def graph_from_latest_report(report: dict) -> tuple[dict[str, dict], list[dict], dict]:
    result = report.get("result", {})
    payload = result.get("claim_graph_payload")

    if payload:
        claims = {
            claim["claim_id"]: claim
            for claim in payload.get("claims", [])
        }
        edges = list(payload.get("edges", []))
        meta = {
            "source": "latest_report",
            "run_id": report.get("run_id"),
            "timestamp_utc": report.get("timestamp_utc"),
            "graph_variant": result.get("graph_variant", "unknown"),
            "summary": payload.get("summary", result.get("claim_graph_summary", {})),
            "support_by_hypothesis": payload.get(
                "support_by_hypothesis",
                result.get("claim_graph_support", {}),
            ),
        }
        return claims, edges, meta

    # backward-compatible fallback for older reports
    variant = result.get("graph_variant", "unknown")
    graph, variant_name = build_reference_claim_graph(
        0 if variant == "baseline" else 1 if variant == "heightened_brigade" else 2
    )

    claims: dict[str, dict] = {}
    edges: list[dict] = []

    for claim in graph.claims.values():
        claims[claim.claim_id] = {
            "claim_id": claim.claim_id,
            "text": claim.text,
            "hypothesis_id": claim.hypothesis_id,
            "tags": claim.tags,
        }

    for edge in graph.edges:
        edges.append(
            {
                "source_claim_id": edge.source_claim_id,
                "target_claim_id": edge.target_claim_id,
                "relation": edge.relation,
                "weight": edge.weight,
            }
        )

    meta = {
        "source": "latest_report_reconstructed",
        "run_id": report.get("run_id"),
        "timestamp_utc": report.get("timestamp_utc"),
        "graph_variant": variant_name,
        "summary": result.get("claim_graph_summary", {}),
        "support_by_hypothesis": result.get("claim_graph_support", {}),
    }
    return claims, edges, meta


def graph_from_reference() -> tuple[dict[str, dict], list[dict], dict]:
    graph, variant_name = build_reference_claim_graph()
    claims: dict[str, dict] = {}
    edges: list[dict] = []

    for claim in graph.claims.values():
        claims[claim.claim_id] = {
            "claim_id": claim.claim_id,
            "text": claim.text,
            "hypothesis_id": claim.hypothesis_id,
            "tags": claim.tags,
        }

    for edge in graph.edges:
        edges.append(
            {
                "source_claim_id": edge.source_claim_id,
                "target_claim_id": edge.target_claim_id,
                "relation": edge.relation,
                "weight": edge.weight,
            }
        )

    meta = {
        "source": "reference_sim",
        "run_id": None,
        "timestamp_utc": None,
        "graph_variant": variant_name,
        "summary": graph.summary(),
        "support_by_hypothesis": {
            hid: graph.support_score_for_hypothesis(hid)
            for hid in sorted({c.hypothesis_id for c in graph.claims.values() if c.hypothesis_id})
        },
    }
    return claims, edges, meta


def load_graph_payload() -> tuple[dict[str, dict], list[dict], dict]:
    report = try_load_latest_report()
    if report is not None:
        return graph_from_latest_report(report)
    return graph_from_reference()


def build_mermaid() -> str:
    claims, edges, meta = load_graph_payload()

    lines: list[str] = []
    lines.append("# Generated Claim Graph")
    lines.append("")
    lines.append(f"- **source**: {meta.get('source')}")
    if meta.get("run_id"):
        lines.append(f"- **run_id**: {meta.get('run_id')}")
    if meta.get("timestamp_utc"):
        lines.append(f"- **timestamp_utc**: {meta.get('timestamp_utc')}")
    lines.append(f"- **graph_variant**: {meta.get('graph_variant')}")
    lines.append("")
    lines.append("```mermaid")
    lines.append("flowchart TD")

    for claim in claims.values():
        nid = sanitize(claim["claim_id"])
        label_parts = [claim["claim_id"], claim["text"].replace('"', "'")]
        if claim.get("hypothesis_id"):
            label_parts.append(f"[{claim['hypothesis_id']}]")
        label = "\\n".join(label_parts)
        lines.append(f'    {nid}["{label}"]')

    for edge in edges:
        src = sanitize(edge["source_claim_id"])
        dst = sanitize(edge["target_claim_id"])
        relation = edge["relation"]
        weight = float(edge.get("weight", 1.0))
        arrow = RELATION_ARROW.get(relation, "-->")
        label = relation_label(relation, weight)
        if arrow == "-->":
            lines.append(f'    {src} -->|"{label}"| {dst}')
        else:
            lines.append(f'    {src} -.->|"{label}"| {dst}')

    lines.append("```")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    summary = meta.get("summary", {})
    for k, v in summary.items():
        lines.append(f"- **{k}**: {v}")

    lines.append("")
    lines.append("## Support by Hypothesis")
    lines.append("")
    support = meta.get("support_by_hypothesis", {})
    for hid in sorted(support.keys()):
        score = support[hid]
        if isinstance(score, float):
            lines.append(f"- **{hid}**: {score:.4f}")
        else:
            lines.append(f"- **{hid}**: {score}")

    return "\n".join(lines)


def main() -> None:
    print(build_mermaid())


if __name__ == "__main__":
    main()
EOF

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  tools/bin/agi observe"
echo "  tools/bin/agi graph"
echo "  tools/bin/agi graph-out"
echo
echo "Suggested commit:"
echo '  git add sim/reference_sim.py sim/observatory/run_logger.py sim/tools/claim_graph_visualizer.py'
echo '  git commit -m "save full AGInet claim graph payload in reports"'
echo "  git pull --no-rebase origin main"
echo "  git push"
