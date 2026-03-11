#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agiscan-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding AGInet scan command"

write_file "$ROOT/tools/bin/agiscan" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== AGINET SCAN ==="
echo

echo "--- STATUS ---"
PYTHONPATH="$ROOT" python -B -m sim.tools.status_summary || true
echo

echo "--- COMPARE (COMPACT) ---"
PYTHONPATH="$ROOT" python -B -m sim.tools.compare_compact || true
echo

echo "--- DRIFT ---"
PYTHONPATH="$ROOT" python -B -m sim.observatory.drift_report || true
EOF

chmod +x "$ROOT/tools/bin/agiscan"

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
alias agiscan='cd ~/projects/AGInet && tools/bin/agiscan'
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
echo "  agiscan"
echo "  agicomparecompact"
echo "  agistatus"
EOF

chmod +x "$ROOT/install_aginet_aliases.sh"

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  bash install_aginet_aliases.sh"
echo "  source ~/.bashrc"
echo "  agiscan"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agiscan install_aginet_aliases.sh'
echo '  git commit -m "add AGInet scan command"'
echo "  git pull --no-rebase origin main"
echo "  git push"
