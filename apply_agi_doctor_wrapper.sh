#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
BACKUP_DIR="$ROOT/.paste-backups/agi-doctor-wrapper-$(date +%Y%m%d-%H%M%S)"

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

echo "[patch] adding AGInet doctor wrapper"

write_file "$ROOT/tools/bin/agi-doctor" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASHRC="$HOME/.bashrc"
LATEST_REPORT="$ROOT/sim/data/latest_report.json"
GRAPH_FILE="$ROOT/docs/generated-claim-graph.md"

ok()   { echo "[ok]   $1"; }
warn() { echo "[warn] $1"; }
info() { echo "[info] $1"; }

echo "=== AGINET DOCTOR ==="
echo

if [ -f "$ROOT/tools/bin/repo-doctor" ]; then
  bash "$ROOT/tools/bin/repo-doctor"
else
  warn "repo-doctor missing at tools/bin/repo-doctor"
fi

echo

if grep -q "# >>> AGINET ALIASES >>>" "$BASHRC" 2>/dev/null; then
  ok "AGInet alias block found in ~/.bashrc"
else
  warn "AGInet alias block not found in ~/.bashrc"
  info "Run: tools/bin/agi-setup"
fi

if [ -f "$LATEST_REPORT" ]; then
  ok "latest report exists: $LATEST_REPORT"
else
  warn "latest report missing: $LATEST_REPORT"
  info "Run: tools/bin/agi observe"
fi

if [ -f "$GRAPH_FILE" ]; then
  ok "graph artifact exists: $GRAPH_FILE"
else
  warn "graph artifact missing: $GRAPH_FILE"
  info "Run: tools/bin/agi graph-out"
fi

echo

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok "git repo detected"
else
  warn "not inside a git repo"
  exit 0
fi

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  warn "repo has uncommitted changes"
else
  ok "repo working tree clean"
fi

REMOTE_URL="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
if [ -n "$REMOTE_URL" ]; then
  ok "git remote configured: $REMOTE_URL"
else
  warn "git remote 'origin' not configured"
fi

if [ -n "$REMOTE_URL" ]; then
  if git -C "$ROOT" ls-remote origin >/dev/null 2>&1; then
    ok "git remote reachable"
  else
    warn "git remote not reachable right now"
    info "Could be network/auth issue"
  fi
fi

echo
echo "Doctor complete."
EOF

chmod +x "$ROOT/tools/bin/agi-doctor"

write_file "$ROOT/tools/bin/agi-setup" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALLER="$ROOT/install_aginet_aliases.sh"

echo "=== AGINET SETUP ==="
echo

if [ ! -f "$INSTALLER" ]; then
  echo "[error] missing installer: $INSTALLER"
  exit 1
fi

bash "$INSTALLER"

echo
echo "[ok] AGInet alias installer ran"
echo
echo "Next:"
echo "  source ~/.bashrc"
echo
echo "Then test:"
echo "  agirefresh"
echo "  agiscan"
echo "  aginetfull"
echo "  tools/bin/agi-doctor"
EOF

chmod +x "$ROOT/tools/bin/agi-setup"

echo
echo "[patch] done"
echo
echo "Next steps:"
echo "  tools/bin/agi-doctor"
echo
echo "Suggested commit:"
echo '  git add tools/bin/agi-doctor tools/bin/agi-setup'
echo '  git commit -m "add AGInet doctor wrapper"'
echo "  git pull --no-rebase origin main"
echo "  git push"
