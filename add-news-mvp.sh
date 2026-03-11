#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/projects/truth-lens"
NEWS_DIR="$ROOT/packages/news/src"
NEWS_FILE="$NEWS_DIR/index.js"
SERVER_FILE="$ROOT/apps/api/src/server.ts"
DASH_FILE="$ROOT/packages/dashboard/src/index.js"

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
    echo "[backup] $file"
  fi
}

mkdir -p "$NEWS_DIR"

cat > "$NEWS_FILE" <<'EOF'
import { detectClusters } from '../../cluster/src/index.js';
import { buildBaselines, compareClusterToBaselines } from '../../baseline/src/index.js';
import { buildSpread } from '../../spread/src/index.js';

function round2(n) {
  return Math.round(n * 100) / 100;
}

function clamp(n, min = 0, max = 1) {
  return Math.max(min, Math.min(max, n));
}

function stateFromScore(score) {
  if (score >= 0.75) return 'critical';
  if (score >= 0.5) return 'escalate';
  if (score >= 0.3) return 'watch';
  return 'observe';
}

function scoreGrowth(postCount) {
  return clamp((postCount - 1) / 7);
}

function scoreAuthors(authorCount) {
  return clamp((authorCount - 1) / 5);
}

function scoreSubreddits(subredditCount) {
  return clamp((subredditCount - 1) / 4);
}

function scoreCompression(spanMinutes, postCount) {
  if (postCount < 2) return 0;
  if (spanMinutes <= 15) return 1;
  if (spanMinutes <= 30) return 0.8;
  if (spanMinutes <= 60) return 0.5;
  if (spanMinutes <= 120) return 0.25;
  return 0;
}

function scoreBaselineDelta(delta) {
  return clamp((delta || 0) / 0.3);
}

export function buildAlerts(posts = [], analyses = []) {
  const baselines = buildBaselines(posts, analyses);
  const clusters = detectClusters(posts, analyses).map((cluster) => ({
    ...cluster,
    baseline: compareClusterToBaselines(cluster, baselines)
  }));
  const spread = buildSpread(posts);
  const spreadMap = new Map(spread.map((x) => [x.id, x]));

  const alerts = clusters.map((cluster, idx) => {
    const s = spreadMap.get(cluster.narrative_id);
    const postCount = cluster.size || 0;
    const authorCount = (cluster.authors || []).length;
    const subredditCount = (cluster.subreddits || []).length;
    const spanMinutes = s?.span_minutes || 0;
    const steeringDelta = cluster.baseline?.steering_delta || 0;

    const growth = scoreGrowth(postCount);
    const authors = scoreAuthors(authorCount);
    const subreddits = scoreSubreddits(subredditCount);
    const compression = scoreCompression(spanMinutes, postCount);
    const baseline = scoreBaselineDelta(steeringDelta);

    const score = round2(
      growth * 0.3 +
      subreddits * 0.2 +
      authors * 0.15 +
      compression * 0.2 +
      baseline * 0.15
    );

    const reason_codes = [];
    if (growth >= 0.5) reason_codes.push('rapid_growth');
    if (subreddits >= 0.5) reason_codes.push('cross_subreddit_jump');
    if (authors >= 0.5) reason_codes.push('author_expansion');
    if (compression >= 0.5) reason_codes.push('time_compression');
    if (baseline >= 0.5) reason_codes.push('above_baseline_steering');

    return {
      id: `alert-${idx + 1}`,
      narrative_id: cluster.narrative_id,
      cluster_id: cluster.id,
      label: cluster.label,
      state: stateFromScore(score),
      score,
      reason_codes,
      metrics: {
        post_count: postCount,
        author_count: authorCount,
        subreddit_count: subredditCount,
        span_minutes: spanMinutes,
        steering_delta: round2(steeringDelta)
      }
    };
  });

  return alerts.sort((a, b) => {
    const rank = { critical: 4, escalate: 3, watch: 2, observe: 1 };
    return rank[b.state] - rank[a.state] || b.score - a.score;
  });
}

export function getAlertById(id, posts = [], analyses = []) {
  return buildAlerts(posts, analyses).find((x) => x.id === id) || null;
}
EOF

echo "[write] $NEWS_FILE"

backup_file "$SERVER_FILE"
backup_file "$DASH_FILE"

python3 - <<'PY'
from pathlib import Path
root = Path.home() / "projects" / "truth-lens"
server_file = root / "apps" / "api" / "src" / "server.ts"
dash_file = root / "packages" / "dashboard" / "src" / "index.js"

server = server_file.read_text()
dash = dash_file.read_text()

news_import = "import { buildAlerts, getAlertById } from '../../../packages/news/src/index.js';"
if news_import not in server:
    anchor = "import { renderDashboard, renderClusterDetail, renderNarrativeDetail } from '../../../packages/dashboard/src/index.js';"
    if anchor in server:
        server = server.replace(anchor, anchor + "\n" + news_import)
        print("[patched] server import")
    else:
        print("[warn] server import anchor not found")

alerts_route = """  if (url.pathname === '/alerts') {
    return json(res, 200, buildAlerts(listPosts(), listAnalysis()));
  }

  if (parts[0] === 'alerts' && parts[1]) {
    const item = getAlertById(parts[1], listPosts(), listAnalysis());
    return item ? json(res, 200, item) : notFound(res);
  }
"""
if "if (url.pathname === '/alerts')" not in server:
    anchor = "  if (url.pathname === '/dashboard') {"
    if anchor in server:
        server = server.replace(anchor, alerts_route + "\n" + anchor, 1)
        print("[patched] /alerts routes")
    else:
        print("[warn] dashboard route anchor not found")

old_payload = """      recent_posts: listRecentPosts(10),
      new_since_last_run: listNewPostsSinceLastRun(10),
      ingest_state: getIngestState()"""
new_payload = """      recent_posts: listRecentPosts(10),
      new_since_last_run: listNewPostsSinceLastRun(10),
      ingest_state: getIngestState(),
      alerts: buildAlerts(posts, analyses)"""
if "alerts: buildAlerts(posts, analyses)" not in server:

