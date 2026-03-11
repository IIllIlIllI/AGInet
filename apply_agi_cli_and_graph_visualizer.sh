#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agi-cli-graph-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] installing AGInet CLI and claim graph visualizer"

write_file "$ROOT/tools/bin/agi" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

usage() {
  cat <<'TXT'
AGInet CLI

Usage:
  tools/bin/agi doctor
  tools/bin/agi run
  tools/bin/agi graph
  tools/bin/agi graph-out
  tools/bin/agi help
TXT
}

case "${1:-help}" in
  doctor)
    bash "$ROOT/tools/bin/repo-doctor"
    ;;
  run)
    PYTHONPATH="$ROOT" python -B -m sim.reference_sim
    ;;
  graph)
    PYTHONPATH="$ROOT" python -B -m sim.tools.claim_graph_visualizer
    ;;
  graph-out)
    PYTHONPATH="$ROOT" python -B -m sim.tools.claim_graph_visualizer > "$ROOT/docs/generated-claim-graph.md"
    echo "[ok] wrote docs/generated-claim-graph.md"
    ;;
  help|*)
    usage
    ;;
esac
EOF

chmod +x "$ROOT/tools/bin/agi"

write_file "$ROOT/tools/bin/agi-graph" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHONPATH="$ROOT" python -B -m sim.tools.claim_graph_visualizer "$@"
EOF

chmod +x "$ROOT/tools/bin/agi-graph"

write_file "$ROOT/sim/tools/claim_graph_visualizer.py" <<'EOF'
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
EOF

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  tools/bin/agi doctor"
echo "  tools/bin/agi run"
echo "  tools/bin/agi graph"
echo "  tools/bin/agi graph-out"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agi tools/bin/agi-graph sim/tools/claim_graph_visualizer.py'
echo '  git commit -m "add AGInet CLI and claim graph visualizer"'
echo "  git push"
