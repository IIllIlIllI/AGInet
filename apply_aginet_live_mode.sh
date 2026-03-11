#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/aginet-live-mode-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding live mode to aginet dashboard"

write_file "$ROOT/tools/bin/aginet" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LATEST_REPORT="$ROOT/sim/data/latest_report.json"
GRAPH_FILE="$ROOT/docs/generated-claim-graph.md"

MODE="${1:-quick}"

usage() {
  cat <<'TXT'
AGInet dashboard

Usage:
  tools/bin/aginet
  tools/bin/aginet quick
  tools/bin/aginet full
  tools/bin/aginet live
TXT
}

case "$MODE" in
  quick|full|live) ;;
  help|-h|--help)
    usage
    exit 0
    ;;
  *)
    echo "[error] unknown mode: $MODE"
    echo
    usage
    exit 1
    ;;
esac

if [ "$MODE" = "live" ]; then
  exec env PYTHONPATH="$ROOT" python -B -m sim.tools.loop_runner
fi

echo "=== AGINET DASHBOARD ($MODE) ==="
echo

echo "--- STATUS ---"
PYTHONPATH="$ROOT" python -B -m sim.tools.status_summary || true
echo

if [ "$MODE" = "full" ]; then
  echo "--- STATUS (FULL) ---"
  PYTHONPATH="$ROOT" python -B -m sim.tools.status_summary --full || true
  echo
fi

echo "--- DRIFT ---"
PYTHONPATH="$ROOT" python -B -m sim.observatory.drift_report || true
echo

echo "--- ARTIFACTS ---"
if [ -f "$LATEST_REPORT" ]; then
  echo "latest_report: $LATEST_REPORT"
else
  echo "latest_report: missing ($LATEST_REPORT)"
fi

if [ -f "$GRAPH_FILE" ]; then
  echo "graph_file:    $GRAPH_FILE"
else
  echo "graph_file:    missing ($GRAPH_FILE)"
fi
EOF

chmod +x "$ROOT/tools/bin/aginet"

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
alias aginet='cd ~/projects/AGInet && tools/bin/aginet'
alias aginetquick='cd ~/projects/AGInet && tools/bin/aginet quick'
alias aginetfull='cd ~/projects/AGInet && tools/bin/aginet full'
alias aginetlive='cd ~/projects/AGInet && tools/bin/aginet live'
alias agirun='cd ~/projects/AGInet && tools/bin/agi run'
alias agiobs='cd ~/projects/AGInet && tools/bin/agi observe'
alias aginspect='cd ~/projects/AGInet && tools/bin/agi inspect'
alias agistatus='cd ~/projects/AGInet && tools/bin/agi status'
alias agistatusfull='cd ~/projects/AGInet && tools/bin/agi status --full'
alias agidrift='cd ~/projects/AGInet && tools/bin/agi drift'
alias agigraph='cd ~/projects/AGInet && tools/bin/agi graph'
alias agigraphout='cd ~/projects/AGInet && tools/bin/agi graph-out'
alias agiwatch='cd ~/projects/AGInet && tools/bin/agi watch'
alias agiloop='cd ~/projects/AGInet && tools/bin/agi loop'
# <<< AGINET ALIASES <<<

ALIASES

echo "[AGInet] Aliases added to ~/.bashrc"
echo
echo "[AGInet] Reload aliases with:"
echo "  source ~/.bashrc"
echo
echo "Try:"
echo "  aginet"
echo "  aginetquick"
echo "  aginetfull"
echo "  aginetlive"
echo "  agistatus"
echo "  agiloop"
EOF

chmod +x "$ROOT/install_aginet_aliases.sh"

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  bash install_aginet_aliases.sh"
echo "  source ~/.bashrc"
echo "  aginetlive"
echo
echo "Suggested commit:"
echo '  git add tools/bin/aginet install_aginet_aliases.sh'
echo '  git commit -m "add live mode to aginet dashboard"'
echo "  git pull --no-rebase origin main"
echo "  git push"
