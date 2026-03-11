#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BASHRC="$HOME/.bashrc"

echo "[AGInet] adding agidoctor alias"

cat >> "$BASHRC" <<'ALIASES'

# --- AGINET DOCTOR SHORTCUT ---
alias agidoctor='cd ~/projects/AGInet && tools/bin/agi-doctor'
# --- END AGINET DOCTOR SHORTCUT ---

ALIASES

echo
echo "[ok] agidoctor alias added"

echo
echo "Reload shell:"
echo "  source ~/.bashrc"

echo
echo "Then run:"
echo "  agidoctor"
