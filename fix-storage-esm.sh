#!/data/data/com.termux/files/usr/bin/bash
set -e

FILE="$HOME/projects/truth-lens/packages/storage/src/storage.js"

echo "[patching ESM exports]"

cp "$FILE" "$FILE.bak.$(date +%Y%m%d-%H%M%S)"

# remove CommonJS exports
sed -i '/module.exports.listRecentPosts/d' "$FILE"
sed -i '/module.exports.listNewPostsSinceLastRun/d' "$FILE"

# convert functions to ESM exports
sed -i 's/function listRecentPosts/export function listRecentPosts/' "$FILE"
sed -i 's/function listNewPostsSinceLastRun/export function listNewPostsSinceLastRun/' "$FILE"

echo "[ESM patch complete]"
