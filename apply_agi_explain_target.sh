#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agi-explain-target-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding targeted hypothesis explanation to AGInet"

write_file "$ROOT/sim/tools/explain_latest.py" <<'EOF'
from __future__ import annotations

import json
import sys
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


def top_hypothesis(posteriors: dict[str, float]) -> tuple[str | None, float]:
    if not posteriors:
        return None, 0.0
    hid = max(posteriors, key=posteriors.get)
    return hid, float(posteriors[hid])


def sorted_posteriors(posteriors: dict[str, float]) -> list[tuple[str, float]]:
    return sorted(posteriors.items(), key=lambda kv: kv[1], reverse=True)


def rank_of(hid: str, ranked: list[tuple[str, float]]) -> int | None:
    for idx, (candidate, _) in enumerate(ranked, start=1):
        if candidate == hid:
            return idx
    return None


def explain_hypothesis(target: str | None) -> None:
    report = load_latest_report()

    print("=== AGINET EXPLAIN ===")

    if report is None:
        print("No latest report found.")
        print(f"Expected file: {LATEST_REPORT}")
        return

    result = report.get("result", {})
    run_id = report.get("run_id")
    variant = result.get("graph_variant")
    posteriors = result.get("posterior_by_hypothesis", {})
    support = result.get("claim_graph_support", {})
    fragility = result.get("fragility_by_hypothesis", {})
    ambiguity = result.get("residual_ambiguity")
    sovereignty = float(result.get("sovereignty_pressure", 0.0))
    contamination = bool(result.get("contamination_flag"))
    audit = result.get("audit", [])

    winner, winner_score = top_hypothesis(posteriors)
    ranked = sorted_posteriors(posteriors)

    if target is None:
        target = winner

    if target is None:
        print("No hypothesis is available to explain.")
        return

    if target not in posteriors:
        print(f"Unknown hypothesis: {target}")
        if ranked:
            print("Available hypotheses:")
            for hid, score in ranked:
                print(f"  {hid}: {score:.4f}")
        return

    target_score = float(posteriors.get(target, 0.0))
    target_support = float(support.get(target, 0.0))
    target_fragility = fragility.get(target, {})
    target_rank = rank_of(target, ranked)

    print(f"run_id:          {run_id}")
    print(f"graph_variant:   {variant}")
    print(f"target:          {target}")
    print(f"target_score:    {target_score:.4f}")
    print(f"target_rank:     {target_rank}")
    print(f"winner:          {winner}")
    print(f"winner_score:    {winner_score:.4f}")
    print("")

    if ranked:
        print("Posterior ranking:")
        for hid, score in ranked:
            marker = " <==" if hid == target else ""
            print(f"  {hid}: {score:.4f}{marker}")
        print("")

    print("Why this hypothesis stands where it does:")
    print(f"  - Graph support score for {target}: {target_support:.4f}")

    if winner is not None:
        margin_vs_winner = target_score - float(posteriors[winner])
        if target == winner:
            print("  - It is the current top-ranked hypothesis.")
            if len(ranked) > 1:
                runner_up, runner_score = ranked[1]
                print(f"  - Margin over runner-up ({runner_up}): {target_score - runner_score:.4f}")
        else:
            print(f"  - It trails the current winner ({winner}) by {-margin_vs_winner:.4f}")

    if target_fragility:
        strongest = max(target_fragility.items(), key=lambda kv: kv[1])
        weakest = min(target_fragility.items(), key=lambda kv: kv[1])
        print(
            f"  - Most load-bearing evidence for {target}: "
            f"{strongest[0]} (fragility {strongest[1]:.4f})"
        )
        print(
            f"  - Least load-bearing evidence for {target}: "
            f"{weakest[0]} (fragility {weakest[1]:.4f})"
        )

    print("")
    print("System conditions:")
    print(f"  - Residual ambiguity: {ambiguity}")
    print(f"  - Sovereignty pressure: {sovereignty:.4f}")
    print(f"  - Contamination flag: {contamination}")

    if ambiguity is not None:
        if int(ambiguity) >= 3:
            print("  - Multiple live hypotheses remain unresolved.")
        elif int(ambiguity) == 2:
            print("  - Narrow uncertainty remains.")
        else:
            print("  - Hypothesis space is relatively resolved.")

    if sovereignty >= 0.62:
        print("  - High sovereignty pressure: treat the explanation cautiously.")
    elif sovereignty >= 0.35:
        print("  - Moderate sovereignty pressure: watch for manipulation or brittle reasoning.")
    else:
        print("  - Low sovereignty pressure: current reasoning conditions look relatively stable.")

    print("")
    print("Support by hypothesis:")
    if support:
        for hid in sorted(support.keys()):
            marker = " <==" if hid == target else ""
            print(f"  {hid}: {support[hid]:.4f}{marker}")
    else:
        print("  No graph support data available.")

    print("")
    print("Relevant audit notes:")
    matched = [
        line for line in audit
        if "sovereignty_note" in line
        or "ambiguity" in line
        or "claim_graph" in line
        or "contamination" in line
        or "posterior" in line
    ]
    if matched:
        for line in matched[-10:]:
            print(f"  {line}")
    else:
        print("  No audit notes found.")

    print("")
    print("Bottom line:")
    if target == winner:
        print(
            f"  {target} is currently leading because it has the strongest posterior "
            "standing in the latest run."
        )
    else:
        print(
            f"  {target} remains live, but it is not currently leading in the latest run."
        )

    if ambiguity is not None and int(ambiguity) >= 2:
        print(
            "  The result is not fully settled because multiple hypotheses still remain live."
        )
    if sovereignty >= 0.35:
        print(
            "  Confidence should also be tempered by sovereignty pressure and fragility indicators."
        )


def main() -> None:
    target = sys.argv[1] if len(sys.argv) > 1 else None
    explain_hypothesis(target)


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
  tools/bin/agi explain [hypothesis_id]
  tools/bin/agi status [--full]
  tools/bin/agi graph
  tools/bin/agi graph-out
  tools/bin/agi watch
  tools/bin/agi loop
  tools/bin/agi help
TXT
}

cmd="${1:-help}"

case "$cmd" in
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
  explain)
    shift || true
    PYTHONPATH="$ROOT" python -B -m sim.tools.explain_latest "$@"
    ;;
  status)
    shift || true
    PYTHONPATH="$ROOT" python -B -m sim.tools.status_summary "$@"
    ;;
  graph)
    PYTHONPATH="$ROOT" python -B -m sim.tools.claim_graph_visualizer
    ;;
  graph-out)
    PYTHONPATH="$ROOT" python -B -m sim.tools.claim_graph_visualizer > "$ROOT/docs/generated-claim-graph.md"
    echo "[ok] wrote docs/generated-claim-graph.md"
    ;;
  watch)
    PYTHONPATH="$ROOT" python -B -m sim.tools.watch_dashboard
    ;;
  loop)
    PYTHONPATH="$ROOT" python -B -m sim.tools.loop_runner
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
echo "  tools/bin/agi explain"
echo "  tools/bin/agi explain h_brigaded"
echo "  tools/bin/agi explain h_verified"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agi sim/tools/explain_latest.py'
echo '  git commit -m "add targeted AGInet hypothesis explanation"'
echo "  git pull --no-rebase origin main"
echo "  git push"
