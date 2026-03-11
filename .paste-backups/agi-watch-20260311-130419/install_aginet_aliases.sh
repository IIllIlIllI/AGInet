#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> AGINET ALIASES >>>"
MARKER_END="# <<< AGINET ALIASES <<<"

echo "[AGInet] Installing shell aliases..."

# Remove previous block if it exists
if grep -q "$MARKER_BEGIN" "$BASHRC"; then
  sed -i "/$MARKER_BEGIN/,/$MARKER_END/d" "$BASHRC"
  echo "[AGInet] Removed previous alias block"
fi

cat >> "$BASHRC" <<'EOF'

# >>> AGINET ALIASES >>>
alias agi='cd ~/projects/AGInet && tools/bin/agi'
alias agirun='cd ~/projects/AGInet && tools/bin/agi run'
alias agiobs='cd ~/projects/AGInet && tools/bin/agi observe'
alias aginspect='cd ~/projects/AGInet && tools/bin/agi inspect'
alias agidrift='cd ~/projects/AGInet && tools/bin/agi drift'
alias agigraph='cd ~/projects/AGInet && tools/bin/agi graph'
alias agigraphout='cd ~/projects/AGInet && tools/bin/agi graph-out'
# <<< AGINET ALIASES <<<

EOF

echo "[AGInet] Aliases added to ~/.bashrc"

# Reload bashrc automatically
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
echo
