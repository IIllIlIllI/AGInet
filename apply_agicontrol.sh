#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agicontrol-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding AGInet control menu"

write_file "$ROOT/tools/bin/agicontrol" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

run_in_root() {
  (cd "$ROOT" && "$@")
}

pause() {
  echo
  read -r -p "Press Enter to return to menu..."
}

header() {
  clear
  echo "=============================="
  echo "       AGINET CONTROL         "
  echo "=============================="
  echo "Repo: $ROOT"
  echo
}

show_menu() {
  echo " 1) Refresh"
  echo " 2) Scan"
  echo " 3) Dashboard Quick"
  echo " 4) Dashboard Full"
  echo " 5) Dashboard Live"
  echo " 6) Status"
  echo " 7) Status Full"
  echo " 8) Compare Compact"
  echo " 9) Compare Full"
  echo "10) Explain Winner"
  echo "11) Explain h_verified"
  echo "12) Explain h_brigaded"
  echo "13) Explain h_uncertain"
  echo "14) Graph Out"
  echo "15) Doctor"
  echo "16) Git Status"
  echo "17) Git Update"
  echo "18) Repo Root Listing"
  echo "19) Run Reference Sim"
  echo "20) Observe"
  echo "21) Drift"
  echo " q) Quit"
  echo
}

while true; do
  header
  show_menu
  read -r -p "Choose an option: " choice

  case "$choice" in
    1)
      run_in_root tools/bin/agirefresh
      pause
      ;;
    2)
      run_in_root tools/bin/agiscan
      pause
      ;;
    3)
      run_in_root tools/bin/aginet quick
      pause
      ;;
    4)
      run_in_root tools/bin/aginet full
      pause
      ;;
    5)
      exec env PYTHONPATH="$ROOT" python -B -m sim.tools.loop_runner
      ;;
    6)
      run_in_root tools/bin/agi status
      pause
      ;;
    7)
      run_in_root tools/bin/agi status --full
      pause
      ;;
    8)
      run_in_root tools/bin/agicompare compact
      pause
      ;;
    9)
      run_in_root tools/bin/agicompare full
      pause
      ;;
    10)
      run_in_root tools/bin/agi explain
      pause
      ;;
    11)
      run_in_root tools/bin/agi explain h_verified
      pause
      ;;
    12)
      run_in_root tools/bin/agi explain h_brigaded
      pause
      ;;
    13)
      run_in_root tools/bin/agi explain h_uncertain
      pause
      ;;
    14)
      run_in_root tools/bin/agi graph-out
      pause
      ;;
    15)
      run_in_root tools/bin/agi-doctor
      pause
      ;;
    16)
      run_in_root git status
      pause
      ;;
    17)
      run_in_root git add .
      if git -C "$ROOT" diff --cached --quiet; then
        echo "[info] no staged changes to commit"
      else
        run_in_root git commit -m "AGInet update"
      fi
      run_in_root git pull --no-rebase origin main || true
      run_in_root git push || true
      pause
      ;;
    18)
      run_in_root ls
      pause
      ;;
    19)
      run_in_root tools/bin/agi run
      pause
      ;;
    20)
      run_in_root tools/bin/agi observe
      pause
      ;;
    21)
      run_in_root tools/bin/agi drift
      pause
      ;;
    q|Q)
      echo "Goodbye."
      exit 0
      ;;
    *)
      echo "Invalid option."
      sleep 1
      ;;
  esac
done
EOF

chmod +x "$ROOT/tools/bin/agicontrol"

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
alias agicontrol='cd ~/projects/AGInet && tools/bin/agicontrol'

alias agirun='cd ~/projects/AGInet && tools/bin/agi run'
alias agiobs='cd ~/projects/AGInet && tools/bin/agi observe'
alias aginspect='cd ~/projects/AGInet && tools/bin/agi inspect'
alias agiexplain='cd ~/projects/AGInet && tools/bin/agi explain'
alias agicompare='cd ~/projects/AGInet && tools/bin/agicompare'
alias agicomparecompact='cd ~/projects/AGInet && tools/bin/agicompare compact'
alias agiscan='cd ~/projects/AGInet && tools/bin/agiscan'
alias agirefresh='cd ~/projects/AGInet && tools/bin/agirefresh'
alias agistatus='cd ~/projects/AGInet && tools/bin/agi status'
alias agistatusfull='cd ~/projects/AGInet && tools/bin/agi status --full'
alias agidrift='cd ~/projects/AGInet && tools/bin/agi drift'
alias agigraph='cd ~/projects/AGInet && tools/bin/agi graph'
alias agigraphout='cd ~/projects/AGInet && tools/bin/agi graph-out'
alias agiwatch='cd ~/projects/AGInet && tools/bin/agi watch'
alias agiloop='cd ~/projects/AGInet && tools/bin/agi loop'
alias agidoctor='cd ~/projects/AGInet && tools/bin/agi-doctor'

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
echo "  agicontrol"
echo "  agirefresh"
echo "  agiscan"
echo "  aginetfull"
EOF

chmod +x "$ROOT/install_aginet_aliases.sh"

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  bash install_aginet_aliases.sh"
echo "  source ~/.bashrc"
echo "  agicontrol"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agicontrol install_aginet_aliases.sh'
echo '  git commit -m "add AGInet control menu"'
echo "  git pull --no-rebase origin main"
echo "  git push"
