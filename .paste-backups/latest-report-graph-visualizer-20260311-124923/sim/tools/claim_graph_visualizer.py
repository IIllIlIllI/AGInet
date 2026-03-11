from __future__ import annotations

from sim.reference_sim import build_reference_claim_graph


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


def build_mermaid() -> str:
    graph = build_reference_claim_graph()
    lines: list[str] = []
    lines.append("# Generated Claim Graph")
    lines.append("")
    lines.append("```mermaid")
    lines.append("flowchart TD")

    for claim in graph.claims.values():
        nid = sanitize(claim.claim_id)
        label = claim.claim_id + "\\n" + claim.text.replace('"', "'")
        lines.append(f'    {nid}["{label}"]')

    for edge in graph.edges:
        src = sanitize(edge.source_claim_id)
        dst = sanitize(edge.target_claim_id)
        arrow = RELATION_ARROW.get(edge.relation, "-->")
        label = relation_label(edge.relation, edge.weight)
        if arrow == "-->":
            lines.append(f'    {src} -->|"{label}"| {dst}')
        else:
            lines.append(f'    {src} -.->|"{label}"| {dst}')

    lines.append("```")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    summary = graph.summary()
    for k, v in summary.items():
        lines.append(f"- **{k}**: {v}")
    lines.append("")
    lines.append("## Support by Hypothesis")
    lines.append("")
    for hid in sorted({c.hypothesis_id for c in graph.claims.values() if c.hypothesis_id}):
        lines.append(f"- **{hid}**: {graph.support_score_for_hypothesis(hid):.4f}")

    return "\n".join(lines)


def main() -> None:
    print(build_mermaid())


if __name__ == "__main__":
    main()
