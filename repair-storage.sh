#!/data/data/com.termux/files/usr/bin/bash
set -e

FILE="$HOME/projects/truth-lens/packages/storage/src/storage.js"

echo "[repairing storage module]"

cp "$FILE" "$FILE.bak.$(date +%Y%m%d-%H%M%S)"

# remove any ESM exports
sed -i 's/export function/function/g' "$FILE"

# remove duplicate module exports
sed -i '/module.exports.listRecentPosts/d' "$FILE"
sed -i '/module.exports.listNewPostsSinceLastRun/d' "$FILE"

# append correct CommonJS exports
echo "" >> "$FILE"
echo "module.exports.listRecentPosts = listRecentPosts;" >> "$FILE"
echo "module.exports.listNewPostsSinceLastRun = listNewPostsSinceLastRun;" >> "$FILE"

echo "[repair complete]"
