#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agi-status-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding AGInet status command"

write_file "$ROOT/sim/tools/status_summary.py" <<'EOF'
from __future__ import annotations

import json
import os
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"
RUN_DIR = ROOT / "sim" / "data" / "run_reports"

RESET = "\033[0m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"


def use_color() -> bool:
    return os.environ.get("AGINET_NO_COLOR", "0") != "1"


def colorize(text: str, color: str) -> str:
    if not use_color():
        return text
    return f"{color}{text}{RESET}"


def glyph(label: str, state: str) -> str:
    palette = {
        "green": GREEN,
        "yellow": YELLOW,
        "red": RED,
    }
    return colorize(label, palette.get(state, ""))


def load_json(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def latest_two_reports() -> list[dict]:
    if not RUN_DIR.exists():
        return []
    reports = []
    for p in sorted(RUN_DIR.glob("run-*.json")):
        obj = load_json(p)
        if obj is not None:
            reports.append(obj)
    return reports[-2:]


def top_hypothesis(posteriors: dict) -> tuple[str | None, float]:
    if not posteriors:
        return None, 0.0
    hid = max(posteriors, key=posteriors.get)
    return hid, float(posteriors[hid])


def main() -> None:
    report = load_json(LATEST_REPORT)
    if report is None:
        print("AGInet status: no latest report found")
        print(f"expected: {LATEST_REPORT}")
        return

    result = report.get("result", {})
    sovereignty = float(result.get("sovereignty_pressure", 0.0))
    contamination = bool(result.get("contamination_flag"))
    ambiguity = int(result.get("residual_ambiguity", 0) or 0)

    graph_summary = result.get("claim_graph_summary", {})
    contradiction_density = float(graph_summary.get("contradiction_density", 0.0) or 0.0)

    recent = latest_two_reports()
    flip = False
    if len(recent) == 2:
        a = recent[0].get("result", {}).get("posterior_by_hypothesis", {})
        b = recent[1].get("result", {}).get("posterior_by_hypothesis", {})
        a_top, _ = top_hypothesis(a)
        b_top, _ = top_hypothesis(b)
        flip = a_top != b_top

    s_state = "red" if sovereignty >= 0.62 else "yellow" if sovereignty >= 0.35 else "green"
    c_state = "red" if contamination else "green"
    a_state = "red" if ambiguity >= 3 else "yellow" if ambiguity >= 2 else "green"
    d_state = "red" if contradiction_density >= 0.30 else "yellow" if contradiction_density >= 0.15 else "green"
    f_state = "red" if flip else "green"

    status_line = "status: " + " ".join([
        f"{glyph('S', s_state)}={sovereignty:.2f}",
        f"{glyph('C', c_state)}={'1' if contamination else '0'}",
        f"{glyph('A', a_state)}={ambiguity}",
        f"{glyph('D', d_state)}={contradiction_density:.2f}",
        f"{glyph('F', f_state)}={'1' if flip else '0'}",
    ])

    print(status_line)
    print(f"run_id: {report.get('run_id')}")
    print(f"graph_variant: {result.get('graph_variant')}")


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
  tools/bin/agi status
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
  status)
    PYTHONPATH="$ROOT" python -B -m sim.tools.status_summary
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
alias agistatus='cd ~/projects/AGInet && tools/bin/agi status'
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
echo "  agistatus"
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
echo "  tools/bin/agi status"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agi sim/tools/status_summary.py install_aginet_aliases.sh'
echo '  git commit -m "add AGInet status command"'
echo "  git pull --no-rebase origin main"
echo "  git push"
