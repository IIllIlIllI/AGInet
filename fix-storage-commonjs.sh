#!/data/data/com.termux/files/usr/bin/bash
set -e

FILE="$HOME/projects/truth-lens/packages/storage/src/storage.js"

echo "[patching] $FILE"

cp "$FILE" "$FILE.bak.$(date +%Y%m%d-%H%M%S)"

echo "[backup created]"

# replace export syntax
sed -i 's/export function listRecentPosts/function listRecentPosts/' "$FILE"
sed -i 's/export function listNewPostsSinceLastRun/function listNewPostsSinceLastRun/' "$FILE"

# append module exports if missing
grep -q "module.exports.listRecentPosts" "$FILE" || echo "module.exports.listRecentPosts = listRecentPosts;" >> "$FILE"
grep -q "module.exports.listNewPostsSinceLastRun" "$FILE" || echo "module.exports.listNewPostsSinceLastRun = listNewPostsSinceLastRun;" >> "$FILE"

echo "[patch complete]"
