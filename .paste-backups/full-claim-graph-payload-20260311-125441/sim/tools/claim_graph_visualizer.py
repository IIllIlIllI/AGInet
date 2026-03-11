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
    variant = result.get("graph_variant", "unknown")
    summary = result.get("claim_graph_summary", {})

    claims: dict[str, dict] = {}
    edges: list[dict] = []

    # Reconstruct a graph shape from the known variant.
    # This keeps visualization aligned with observed runs even before
    # full edge-level graph serialization exists in latest_report.json.
    graph, variant_name = build_reference_claim_graph(
        0 if variant == "baseline" else 1 if variant == "heightened_brigade" else 2
    )

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
        "source": "latest_report",
        "run_id": report.get("run_id"),
        "timestamp_utc": report.get("timestamp_utc"),
        "graph_variant": variant_name,
        "summary": summary,
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
