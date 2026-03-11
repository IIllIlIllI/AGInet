#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agicompare-compact-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding compact mode to AGInet compare"

write_file "$ROOT/sim/tools/compare_compact.py" <<'EOF'
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path.cwd()
LATEST_REPORT = ROOT / "sim" / "data" / "latest_report.json"
TARGETS = ["h_verified", "h_brigaded", "h_uncertain"]


def load_latest_report() -> dict | None:
    if not LATEST_REPORT.exists():
        return None
    try:
        return json.loads(LATEST_REPORT.read_text(encoding="utf-8"))
    except Exception:
        return None


def rank_map(posteriors: dict[str, float]) -> dict[str, int]:
    ranked = sorted(posteriors.items(), key=lambda kv: kv[1], reverse=True)
    return {hid: idx for idx, (hid, _) in enumerate(ranked, start=1)}


def main() -> None:
    report = load_latest_report()

    print("=== AGINET COMPARE (COMPACT) ===")

    if report is None:
        print("No latest report found.")
        print(f"Expected file: {LATEST_REPORT}")
        return

    result = report.get("result", {})
    posteriors = result.get("posterior_by_hypothesis", {})
    support = result.get("claim_graph_support", {})
    fragility = result.get("fragility_by_hypothesis", {})
    ambiguity = result.get("residual_ambiguity")
    sovereignty = float(result.get("sovereignty_pressure", 0.0))
    contamination = bool(result.get("contamination_flag"))
    variant = result.get("graph_variant")

    ranks = rank_map(posteriors)

    print(f"run_id:              {report.get('run_id')}")
    print(f"graph_variant:       {variant}")
    print(f"residual_ambiguity:  {ambiguity}")
    print(f"sovereignty:         {sovereignty:.4f}")
    print(f"contamination:       {contamination}")
    print("")
    print("hypothesis      rank  posterior  support   max_fragility  strongest_evidence")
    print("--------------------------------------------------------------------------")

    for hid in TARGETS:
        posterior = float(posteriors.get(hid, 0.0))
        support_score = float(support.get(hid, 0.0))
        frag = fragility.get(hid, {})
        if frag:
            strongest_evidence, strongest_value = max(frag.items(), key=lambda kv: kv[1])
        else:
            strongest_evidence, strongest_value = "-", 0.0

        print(
            f"{hid:<15} "
            f"{str(ranks.get(hid, '-')):<5} "
            f"{posterior:<10.4f} "
            f"{support_score:<8.4f} "
            f"{strongest_value:<13.4f} "
            f"{strongest_evidence}"
        )


if __name__ == "__main__":
    main()
EOF

write_file "$ROOT/tools/bin/agicompare" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-full}"

usage() {
  cat <<'TXT'
AGInet compare

Usage:
  tools/bin/agicompare
  tools/bin/agicompare full
  tools/bin/agicompare compact
TXT
}

case "$MODE" in
  full)
    echo "=== AGINET COMPARE ==="
    echo

    echo "--- h_verified ---"
    PYTHONPATH="$ROOT" python -B -m sim.tools.explain_latest h_verified || true
    echo

    echo "--- h_brigaded ---"
    PYTHONPATH="$ROOT" python -B -m sim.tools.explain_latest h_brigaded || true
    echo

    echo "--- h_uncertain ---"
    PYTHONPATH="$ROOT" python -B -m sim.tools.explain_latest h_uncertain || true
    ;;
  compact)
    PYTHONPATH="$ROOT" python -B -m sim.tools.compare_compact
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "[error] unknown mode: $MODE"
    echo
    usage
    exit 1
    ;;
esac
EOF

chmod +x "$ROOT/tools/bin/agicompare"

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
alias agicompare='cd ~/projects/AGInet && tools/bin/agicompare'
alias agicomparecompact='cd ~/projects/AGInet && tools/bin/agicompare compact'
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

alias agixv='cd ~/projects/AGInet && tools/bin/agi explain h_verified'
alias agixb='cd ~/projects/AGInet && tools/bin/agi explain h_brigaded'
alias agixu='cd ~/projects/AGInet && tools/bin/agi explain h_uncertain'

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
echo "  agicompare"
echo "  agicomparecompact"
EOF

chmod +x "$ROOT/install_aginet_aliases.sh"

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  bash install_aginet_aliases.sh"
echo "  source ~/.bashrc"
echo "  agicompare"
echo "  agicomparecompact"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agicompare sim/tools/compare_compact.py install_aginet_aliases.sh'
echo '  git commit -m "add compact AGInet compare mode"'
echo "  git pull --no-rebase origin main"
echo "  git push"
