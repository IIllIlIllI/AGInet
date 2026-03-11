#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/projects/truth-lens"
FETCHER="$ROOT/packages/reddit/src/fetch.ts"
ENVFILE="$ROOT/.env"

cp "$FETCHER" "$FETCHER.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

cat > "$FETCHER" <<'EOF'
const USER_AGENT =
  process.env.REDDIT_USER_AGENT || "truth-lens/0.1 (Termux prototype)";

function normalizePost(d) {
  return {
    id: String(d.id || ""),
    subreddit: String(d.subreddit || ""),
    author: String(d.author || ""),
    title: String(d.title || ""),
    body: String(d.selftext || ""),
    created_at: d.created_utc
      ? new Date(d.created_utc * 1000).toISOString()
      : new Date().toISOString(),
    permalink: d.permalink
      ? `https://www.reddit.com${d.permalink}`
      : "",
    score: Number(d.score || 0),
    num_comments: Number(d.num_comments || 0),
    url: String(d.url || "")
  };
}

export async function fetchSubredditNew(subreddit) {
  const clean = String(subreddit || "").trim().replace(/^r\//, "");
  if (!clean) return [];

  const url = `https://www.reddit.com/r/${encodeURIComponent(clean)}/new.json?limit=10`;

  const res = await fetch(url, {
    headers: {
      "User-Agent": USER_AGENT,
      "Accept": "application/json"
    }
  });

  if (!res.ok) {
    throw new Error(`Reddit fetch failed for r/${clean}: ${res.status}`);
  }

  const json = await res.json();
  const children = json?.data?.children || [];

  return children
    .map((item) => normalizePost(item?.data || {}))
    .filter((post) => post.id);
}
EOF

if [ ! -f "$ENVFILE" ]; then
  touch "$ENVFILE"
fi

grep -q '^REDDIT_USER_AGENT=' "$ENVFILE" || echo 'REDDIT_USER_AGENT=truth-lens/0.1 (Termux prototype)' >> "$ENVFILE"
grep -q '^PILOT_SUBREDDITS=' "$ENVFILE" || echo 'PILOT_SUBREDDITS=technology,news,gaming' >> "$ENVFILE"

echo "[done] real reddit fetcher enabled"
echo "Now run:"
echo "  cd $ROOT"
echo "  node apps/worker/src/worker.ts"
echo "Then:"
echo "  node apps/api/src/server.ts"
