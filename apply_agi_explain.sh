#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agi-explain-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding AGInet explain command"

write_file "$ROOT/sim/tools/explain_latest.py" <<'EOF'
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


def top_hypothesis(posteriors: dict[str, float]) -> tuple[str | None, float]:
    if not posteriors:
        return None, 0.0
    hid = max(posteriors, key=posteriors.get)
    return hid, float(posteriors[hid])


def sorted_posteriors(posteriors: dict[str, float]) -> list[tuple[str, float]]:
    return sorted(posteriors.items(), key=lambda kv: kv[1], reverse=True)


def main() -> None:
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

    print(f"run_id:          {run_id}")
    print(f"graph_variant:   {variant}")
    print(f"winner:          {winner}")
    print(f"winner_score:    {winner_score:.4f}")
    print("")

    if ranked:
        print("Posterior ranking:")
        for hid, score in ranked:
            print(f"  {hid}: {score:.4f}")
        print("")

    print("Why it won:")
    if winner is None:
        print("  No winner could be determined.")
    else:
        top_support = support.get(winner, 0.0)
        print(f"  - {winner} has the highest posterior probability in the latest run.")
        print(f"  - Graph support score for {winner}: {top_support:.4f}")

        if len(ranked) > 1:
            runner_up, runner_score = ranked[1]
            margin = winner_score - runner_score
            print(f"  - Margin over runner-up ({runner_up}): {margin:.4f}")

        winner_fragility = fragility.get(winner, {})
        if winner_fragility:
            strongest = max(winner_fragility.items(), key=lambda kv: kv[1])
            print(
                f"  - Most load-bearing evidence for {winner}: "
                f"{strongest[0]} (fragility {strongest[1]:.4f})"
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
        print("  - High sovereignty pressure: explanation should be treated cautiously.")
    elif sovereignty >= 0.35:
        print("  - Moderate sovereignty pressure: watch for manipulation or brittle reasoning.")
    else:
        print("  - Low sovereignty pressure: current reasoning conditions look relatively stable.")

    print("")
    print("Support by hypothesis:")
    if support:
        for hid in sorted(support.keys()):
            print(f"  {hid}: {support[hid]:.4f}")
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
    ]
    if matched:
        for line in matched[-8:]:
            print(f"  {line}")
    else:
        print("  No audit notes found.")

    print("")
    print("Bottom line:")
    if winner is None:
        print("  The system does not currently have a usable explanation.")
    else:
        print(
            f"  {winner} is leading because it currently has the strongest combined "
            "posterior standing in the latest run."
        )
        if ambiguity is not None and int(ambiguity) >= 2:
            print(
                "  However, the result is not fully settled because multiple hypotheses "
                "still remain live."
            )
        if sovereignty >= 0.35:
            print(
                "  Confidence should also be tempered by sovereignty pressure and "
                "fragility indicators."
            )


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
  tools/bin/agi explain
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
    PYTHONPATH="$ROOT" python -B -m sim.tools.explain_latest
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

write_file "$ROOT/install_aginet_aliases.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> AGINET ALIASES >>>"
MARKER_END="# <<< AGINET ALIASES <<<"

echo "[AGInet] Installing shell aliases..."

touch "$BASHRC"

if grep -q "$MARKER_BEGIN" "$BASHRC"; then
  sed -i "/$MARKER_BEGIN/,/$MARKER_END/d" "$BASHRC"
  echo "[AGInet] Removed previous AGINET alias block"
fi

cat >> "$BASHRC" <<'ALIASES'

# >>> AGINET ALIASES >>>
alias agi='cd ~/projects/AGInet && tools/bin/agi'
alias aginet='cd ~/projects/AGInet && tools/bin/aginet'
alias aginetquick='cd ~/projects/AGInet && tools/bin/aginet quick'
alias aginetfull='cd ~/projects/AGInet && tools/bin/aginet full'
alias aginetlive='cd ~/projects/AGInet && tools/bin/aginet live'
alias aginetfast='cd ~/projects/AGInet && AGINET_LOOP_INTERVAL=2 tools/bin/aginet live'

alias agirun='cd ~/projects/AGInet && tools/bin/agi run'
alias agiobs='cd ~/projects/AGInet && tools/bin/agi observe'
alias aginspect='cd ~/projects/AGInet && tools/bin/agi inspect'
alias agiexplain='cd ~/projects/AGInet && tools/bin/agi explain'
alias agistatus='cd ~/projects/AGInet && tools/bin/agi status'
alias agistatusfull='cd ~/projects/AGInet && tools/bin/agi status --full'
alias agidrift='cd ~/projects/AGInet && tools/bin/agi drift'
alias agigraph='cd ~/projects/AGInet && tools/bin/agi graph'
alias agigraphout='cd ~/projects/AGInet && tools/bin/agi graph-out'
alias agiwatch='cd ~/projects/AGInet && tools/bin/agi watch'
alias agiloop='cd ~/projects/AGInet && tools/bin/agi loop'

alias agdoc='cd ~/projects/AGInet && bash tools/bin/repo-doctor'
alias agroot='cd ~/projects/AGInet'
alias agls='ls ~/projects/AGInet'

alias ags='cd ~/projects/AGInet && git status'
alias aga='cd ~/projects/AGInet && git add .'
alias agc='cd ~/projects/AGInet && git commit -m'
alias agp='cd ~/projects/AGInet && git push'
alias agpull='cd ~/projects/AGInet && git pull --no-rebase origin main'
alias agupdate='cd ~/projects/AGInet && git add . && git commit -m "AGInet update" && git pull --no-rebase origin main && git push'

agpy() {
  cd ~/projects/AGInet && PYTHONPATH="$(pwd)" python -B -m "$@"
}
# <<< AGINET ALIASES <<<

ALIASES

echo
echo "[AGInet] Alias block written to $BASHRC"
echo "[AGInet] Reload with:"
echo "  source ~/.bashrc"
echo
echo "Then try:"
echo "  agiexplain"
echo "  agistatus"
echo "  aginetfull"
EOF

chmod +x "$ROOT/install_aginet_aliases.sh"

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  bash install_aginet_aliases.sh"
echo "  source ~/.bashrc"
echo "  tools/bin/agi explain"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agi sim/tools/explain_latest.py install_aginet_aliases.sh'
echo '  git commit -m "add AGInet explain command"'
echo "  git pull --no-rebase origin main"
echo "  git push"
