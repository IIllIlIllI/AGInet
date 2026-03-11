#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
TARGET="$ROOT/install_aginet_aliases.sh"
BACKUP_DIR="$ROOT/.paste-backups/agistatusfull-alias-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

if [ -f "$TARGET" ]; then
  cp "$TARGET" "$BACKUP_DIR/install_aginet_aliases.sh.bak"
  echo "[backup] install_aginet_aliases.sh"
fi

cat > "$TARGET" <<'EOF'
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
alias agistatusfull='cd ~/projects/AGInet && tools/bin/agi status --full'
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
echo "  agistatusfull"
echo "  agidrift"
echo "  agigraph"
echo "  agiwatch"
echo "  agiloop"
EOF

chmod +x "$TARGET"

echo
echo "[patch] done"
echo "Next steps:"
echo "  bash install_aginet_aliases.sh"
echo "  agistatusfull"
