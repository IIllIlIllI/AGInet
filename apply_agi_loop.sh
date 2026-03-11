#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agi-loop-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding AGInet loop runner"

write_file "$ROOT/sim/tools/loop_runner.py" <<'EOF'
from __future__ import annotations

import json
import os
import subprocess
import time
from datetime import datetime, UTC
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"
GRAPH_OUT = ROOT / "docs" / "generated-claim-graph.md"


def clear() -> None:
    os.system("clear")


def run_command(args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(args, capture_output=True, text=True)
    output = (proc.stdout or "") + (proc.stderr or "")
    return proc.returncode, output.strip()


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


def render(report: dict | None, interval: float, iteration: int, observe_ok: bool, graph_ok: bool) -> str:
    now = datetime.now(UTC).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines: list[str] = []
    lines.append("=== AGINET LOOP ===")
    lines.append(f"time: {now}")
    lines.append(f"iteration: {iteration}")
    lines.append(f"refresh_interval_sec: {interval}")
    lines.append(f"observe_status: {'ok' if observe_ok else 'fail'}")
    lines.append(f"graph_out_status: {'ok' if graph_ok else 'fail'}")
    lines.append("press Ctrl+C to stop")
    lines.append("")

    if report is None:
        lines.append("No latest report found.")
        lines.append(f"Expected file: {LATEST_REPORT}")
        return "\n".join(lines)

    result = report.get("result", {})
    posteriors = result.get("posterior_by_hypothesis", {})
    top_id, top_score = top_hypothesis(posteriors)
    graph_summary = result.get("claim_graph_summary", {})
    support = result.get("claim_graph_support", {})

    lines.append(f"run_id:                {report.get('run_id')}")
    lines.append(f"timestamp_utc:         {report.get('timestamp_utc')}")
    lines.append(f"graph_variant:         {result.get('graph_variant')}")
    lines.append(f"top_hypothesis:        {top_id}")
    lines.append(f"top_score:             {top_score:.4f}")
    lines.append(f"residual_ambiguity:    {result.get('residual_ambiguity')}")
    lines.append(f"sovereignty_pressure:  {float(result.get('sovereignty_pressure', 0.0)):.4f}")
    lines.append(f"contamination_flag:    {result.get('contamination_flag')}")
    lines.append(f"claim_count:           {graph_summary.get('claim_count')}")
    lines.append(f"edge_count:            {graph_summary.get('edge_count')}")
    lines.append(f"contradiction_density: {graph_summary.get('contradiction_density')}")
    lines.append(f"graph_file:            {GRAPH_OUT}")
    lines.append("")

    if support:
        lines.append("Support by hypothesis:")
        for hid in sorted(support.keys()):
            score = support[hid]
            if isinstance(score, float):
                lines.append(f"  {hid:<14} {score:>7.4f}")
            else:
                lines.append(f"  {hid:<14} {score}")
        lines.append("")

    audit = result.get("audit", [])
    if audit:
        lines.append("Recent audit lines:")
        for line in audit[-6:]:
            lines.append(f"  {line}")

    return "\n".join(lines)


def main() -> None:
    interval = float(os.environ.get("AGINET_LOOP_INTERVAL", "5"))
    iteration = 0
    root_str = str(ROOT)

    try:
        while True:
            iteration += 1

            observe_code, _ = run_command(
                ["python", "-B", "-m", "sim.observatory.run_logger"]
            )
            graph_code, _ = run_command(
                ["python", "-B", "-m", "sim.tools.claim_graph_visualizer"]
            )

            if graph_code == 0:
                # write fresh graph artifact
                proc = subprocess.run(
                    ["python", "-B", "-m", "sim.tools.claim_graph_visualizer"],
                    capture_output=True,
                    text=True,
                    cwd=root_str,
                    env={**os.environ, "PYTHONPATH": root_str},
                )
                if proc.returncode == 0:
                    GRAPH_OUT.parent.mkdir(parents=True, exist_ok=True)
                    GRAPH_OUT.write_text(proc.stdout, encoding="utf-8")
                else:
                    graph_code = proc.returncode

            report = load_latest_report()
            clear()
            print(
                render(
                    report,
                    interval=interval,
                    iteration=iteration,
                    observe_ok=(observe_code == 0),
                    graph_ok=(graph_code == 0),
                )
            )
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\n[ok] loop stopped")


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
  tools/bin/agi watch
  tools/bin/agi loop
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

if grep -q "$MARKER_BEGIN" "$BASHRC"; then
  sed -i "/$MARKER_BEGIN/,/$MARKER_END/d" "$BASHRC"
  echo "[AGInet] Removed previous alias block"
fi

cat >> "$BASHRC" <<'ALIASES'

# >>> AGINET ALIASES >>>
alias agi='cd ~/projects/AGInet && tools/bin/agi'
alias agirun='cd ~/projects/AGInet && tools/bin/agi run'
alias agiobs='cd ~/projects/AGInet && tools/bin/agi observe'
alias aginspect='cd ~/projects/AGInet && tools/bin/agi inspect'
alias agidrift='cd ~/projects/AGInet && tools/bin/agi drift'
alias agigraph='cd ~/projects/AGInet && tools/bin/agi graph'
alias agigraphout='cd ~/projects/AGInet && tools/bin/agi graph-out'
alias agiwatch='cd ~/projects/AGInet && tools/bin/agi watch'
alias agiloop='cd ~/projects/AGInet && tools/bin/agi loop'
# <<< AGINET ALIASES <<<

ALIASES

echo "[AGInet] Aliases added to ~/.bashrc"
# shellcheck disable=SC1090
source "$BASHRC"

echo
echo "[AGInet] Aliases ready."
echo
echo "Try:"
echo "  agi doctor"
echo "  agirun"
echo "  agiobs"
echo "  aginspect"
echo "  agidrift"
echo "  agigraph"
echo "  agiwatch"
echo "  agiloop"
EOF

chmod +x "$ROOT/install_aginet_aliases.sh"

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  bash install_aginet_aliases.sh"
echo "  tools/bin/agi loop"
echo
echo "Optional speed control:"
echo "  AGINET_LOOP_INTERVAL=2 tools/bin/agi loop"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agi sim/tools/loop_runner.py install_aginet_aliases.sh'
echo '  git commit -m "add AGInet loop runner"'
echo "  git pull --no-rebase origin main"
echo "  git push"
