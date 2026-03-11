#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agi-inspect-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding AGInet inspect command"

write_file "$ROOT/sim/tools/inspect_latest_report.py" <<'EOF'
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"


def load_latest_report() -> dict | None:
    if not LATEST_REPORT.exists():
        return None
    try:
        return json.loads(LATEST_REPORT.read_text(encoding="utf-8"))
    except Exception:
        return None


def top_hypothesis(posteriors: dict) -> tuple[str | None, float]:
    if not posteriors:
        return None, 0.0
    hid = max(posteriors, key=posteriors.get)
    return hid, float(posteriors[hid])


def main() -> None:
    report = load_latest_report()
    print("=== AGINET INSPECT ===")

    if report is None:
        print("No latest report found.")
        print(f"Expected file: {LATEST_REPORT}")
        return

    result = report.get("result", {})
    posteriors = result.get("posterior_by_hypothesis", {})
    top_id, top_score = top_hypothesis(posteriors)

    graph_summary = result.get("claim_graph_summary", {})
    contradiction_density = graph_summary.get("contradiction_density")
    claim_count = graph_summary.get("claim_count")
    edge_count = graph_summary.get("edge_count")

    print(f"run_id:                {report.get('run_id')}")
    print(f"timestamp_utc:         {report.get('timestamp_utc')}")
    print(f"graph_variant:         {result.get('graph_variant')}")
    print(f"top_hypothesis:        {top_id}")
    print(f"top_score:             {top_score:.4f}")
    print(f"residual_ambiguity:    {result.get('residual_ambiguity')}")
    print(f"sovereignty_pressure:  {float(result.get('sovereignty_pressure', 0.0)):.4f}")
    print(f"contamination_flag:    {result.get('contamination_flag')}")
    print(f"claim_count:           {claim_count}")
    print(f"edge_count:            {edge_count}")
    print(f"contradiction_density: {contradiction_density}")

    support = result.get("claim_graph_support", {})
    if support:
        print("\nSupport by hypothesis:")
        for hid in sorted(support.keys()):
            score = support[hid]
            if isinstance(score, float):
                print(f"  {hid}: {score:.4f}")
            else:
                print(f"  {hid}: {score}")


if __name__ == "__main__":
    main()
EOF

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
  tools/bin/agi observe
  tools/bin/agi drift
  tools/bin/agi inspect
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
  observe)
    PYTHONPATH="$ROOT" python -B -m sim.observatory.run_logger
    ;;
  drift)
    PYTHONPATH="$ROOT" python -B -m sim.observatory.drift_report
    ;;
  inspect)
    PYTHONPATH="$ROOT" python -B -m sim.tools.inspect_latest_report
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

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  tools/bin/agi observe"
echo "  tools/bin/agi inspect"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agi sim/tools/inspect_latest_report.py'
echo '  git commit -m "add AGInet inspect command"'
echo "  git pull --no-rebase origin main"
echo "  git push"
