#!/data/data/com.termux/files/usr/bin/bash
set -e

SERVER="$HOME/projects/truth-lens/apps/api/src/server.ts"

echo "[repairing missing module imports]"

cp "$SERVER" "$SERVER.bak.$(date +%s)"

# Remove optional imports if modules don't exist
sed -i '/packages\/signatures/d' "$SERVER"
sed -i '/packages\/fingerprints/d' "$SERVER"
sed -i '/packages\/tracing/d' "$SERVER"

# Remove routes referencing those modules
sed -i '/\/signatures/d' "$SERVER"
sed -i '/\/fingerprints/d' "$SERVER"
sed -i '/\/traces/d' "$SERVER"

echo "[optional modules removed]"
