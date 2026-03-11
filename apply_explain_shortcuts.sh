#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BASHRC="$HOME/.bashrc"

echo "[AGInet] installing explain shortcut aliases"

cat >> "$BASHRC" <<'ALIASES'

# --- AGINET EXPLAIN SHORTCUTS ---
alias agixv='cd ~/projects/AGInet && tools/bin/agi explain h_verified'
alias agixb='cd ~/projects/AGInet && tools/bin/agi explain h_brigaded'
alias agixu='cd ~/projects/AGInet && tools/bin/agi explain h_uncertain'
# --- END AGINET EXPLAIN SHORTCUTS ---

ALIASES

echo "[AGInet] shortcuts added"

echo
echo "Reload shell:"
echo "  source ~/.bashrc"
echo
echo "Then test:"
echo "  agixv"
echo "  agixb"
echo "  agixu"
