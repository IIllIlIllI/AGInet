#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/projects/truth-lens"

STORAGE="$ROOT/packages/storage/src/storage.js"
SERVER="$ROOT/apps/api/src/server.ts"
DASH="$ROOT/packages/dashboard/src/index.js"

backup() {
  local file="$1"
  cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
  echo "[backup] $file"
}

backup "$STORAGE"
backup "$SERVER"
backup "$DASH"

python <<'PY'
from pathlib import Path

root = Path.home() / "projects" / "truth-lens"
storage = root / "packages" / "storage" / "src" / "storage.js"
server = root / "apps" / "api" / "src" / "server.ts"
dash = root / "packages" / "dashboard" / "src" / "index.js"

# -----------------
# storage.js patch
# -----------------
s = storage.read_text()

append_block = r"""

export function listRecentPosts(limit = 10) {
  return listPosts()
    .sort((a, b) => {
      const ax = new Date(a.last_seen_at || a.updated_at || a.created_at || 0).getTime();
      const bx = new Date(b.last_seen_at || b.updated_at || b.created_at || 0).getTime();
      return bx - ax;
    })
    .slice(0, limit);
}

export function listNewPostsSinceLastRun(limit = 10) {
  const state = getIngestState();
  const lastRun = state?.last_run_at ? new Date(state.last_run_at).getTime() : 0;

  return listPosts()
    .filter((p) => {
      const firstSeen = new Date(p.first_seen_at || 0).getTime();
      return firstSeen >= lastRun;
    })
    .sort((a, b) => {
      const ax = new Date(a.first_seen_at || 0).getTime();
      const bx = new Date(b.first_seen_at || 0).getTime();
      return bx - ax;
    })
    .slice(0, limit);
}
""".strip("\n")

if "export function listRecentPosts(limit = 10)" not in s:
    s = s.rstrip() + "\n\n" + append_block + "\n"
    storage.write_text(s)
    print("[patched] storage.js")
else:
    print("[skip] storage.js already has activity helpers")

# -----------------
# server.ts patch
# -----------------
srv = server.read_text()

old_import = "import { listPosts, getPost, listAnalysis, getAnalysis } from '../../../packages/storage/src/storage.js';"
new_import = """import {
  listPosts,
  getPost,
  listAnalysis,
  getAnalysis,
  getIngestState,
  listRecentPosts,
  listNewPostsSinceLastRun
} from '../../../packages/storage/src/storage.js';"""
if old_import in srv and "listRecentPosts" not in srv:
    srv = srv.replace(old_import, new_import)
    print("[patched] server import block")
elif "listRecentPosts" in srv:
    print("[skip] server import block already patched")
else:
    print("[warn] server import block not found exactly")

activity_block = """
  if (url.pathname === '/activity') {
    return json(res, 200, {
      ingest_state: getIngestState(),
      recent_posts: listRecentPosts(10),
      new_since_last_run: listNewPostsSinceLastRun(10)
    });
  }
""".strip("\n")

summary_anchor = """  if (url.pathname === '/summary') {
    return json(res, 200, summarize(listAnalysis()));
  }
"""
if "if (url.pathname === '/activity')" not in srv:
    if summary_anchor in srv:
        srv = srv.replace(summary_anchor, summary_anchor + "\n" + activity_block + "\n")
        print("[patched] /activity route")
    else:
        print("[warn] summary anchor not found for /activity route")
else:
    print("[skip] /activity route already exists")

dashboard_old = """    return html(res, 200, renderDashboard({
      summary: summaryData,
      baselines,
      clusters,
      spread,
      cluster_findings: findings.cluster_findings,
      narrative_findings: findings.narrative_findings
    }, {"""
dashboard_new = """    return html(res, 200, renderDashboard({
      summary: summaryData,
      baselines,
      clusters,
      spread,
      cluster_findings: findings.cluster_findings,
      narrative_findings: findings.narrative_findings,
      recent_posts: listRecentPosts(10),
      new_since_last_run: listNewPostsSinceLastRun(10),
      ingest_state: getIngestState()
    }, {"""
if "recent_posts: listRecentPosts(10)" not in srv:
    if dashboard_old in srv:
        srv = srv.replace(dashboard_old, dashboard_new)
        print("[patched] dashboard data payload")
    else:
        print("[warn] dashboard payload anchor not found")
else:
    print("[skip] dashboard data payload already patched")

routes_old = """      '/summary',"""
routes_new = """      '/summary',
      '/activity',"""
if "'/activity'" not in srv:
    # only patch the fallback routes array, first occurrence after summary route list
    idx = srv.find("'/summary'")
    if idx != -1:
        srv = srv[:idx] + srv[idx:].replace(routes_old, routes_new, 1)
        print("[patched] fallback routes list")
    else:
        print("[warn] fallback routes list anchor not found")
else:
    print("[skip] fallback routes already include /activity")

server.write_text(srv)

# -----------------
# dashboard patch
# -----------------
d = dash.read_text()

anchor = "  const baselines = subreddit"
insertion = """  const recentPosts = data.recent_posts || [];
  const newSinceLastRun = data.new_since_last_run || [];
  const ingestState = data.ingest_state || {};

  const baselines = subreddit"""
if "const recentPosts = data.recent_posts || [];" not in d:
    if anchor in d:
        d = d.replace(anchor, insertion, 1)
        print("[patched] dashboard data locals")
    else:
        print("[warn] dashboard baselines anchor not found")
else:
    print("[skip] dashboard data locals already patched")

if "const activityHtml = `" not in d:
    marker = "  const searchHtml = q"
    block = """  const activityHtml = `
    <p><strong>Last run:</strong> ${esc(ingestState.last_run_at || 'never')}</p>
    ${list(Object.entries(ingestState.subreddits || {}).map(([sub, info]) => {
      return `<strong>r/${esc(sub)}</strong><br><span>fetched=${esc(info.fetched_count ?? 0)} created=${esc(info.created_count ?? 0)} updated=${esc(info.updated_count ?? 0)}</span>`;
    }))}
  `;

  const newPostsHtml = list(newSinceLastRun.map((p) => {
    return `<strong>${esc(p.title || p.id)}</strong><br><span>r/${esc(p.subreddit)} by ${esc(p.author)}</span><br><span class="muted">first_seen=${esc(p.first_seen_at || '')}</span>`;
  }));

  const recentPostsHtml = list(recentPosts.map((p) => {
    return `<strong>${esc(p.title || p.id)}</strong><br><span>r/${esc(p.subreddit)} by ${esc(p.author)}</span><br><span class="muted">last_seen=${esc(p.last_seen_at || p.updated_at || '')} seen_count=${esc(p.seen_count ?? 0)}</span>`;
  }));

"""
    if marker in d:
        d = d.replace(marker, block + marker, 1)
        print("[patched] dashboard activity html blocks")
    else:
        print("[warn] dashboard searchHtml anchor not found")
else:
    print("[skip] dashboard activity html blocks already exist")

old_cards = """  ${card('PRO TIP', proTipHtml)}
  ${card('Summary', summaryHtml)}
  ${card('Controls', controlsHtml)}"""
new_cards = """  ${card('PRO TIP', proTipHtml)}
  ${card('Summary', summaryHtml)}
  ${card('Recent Activity', activityHtml)}
  ${card('New Since Last Run', newPostsHtml)}
  ${card('Recently Seen Posts', recentPostsHtml)}
  ${card('Controls', controlsHtml)}"""
if "${card('Recent Activity', activityHtml)}" not in d:
    if old_cards in d:
        d = d.replace(old_cards, new_cards, 1)
        print("[patched] dashboard cards")
    else:
        print("[warn] dashboard card anchor not found")
else:
    print("[skip] dashboard cards already patched")

dash.write_text(d)
PY

echo
echo "Done."
echo "Now restart:"
echo "  cd ~/projects/truth-lens"
echo "  node apps/worker/src/worker.ts"
echo "  node apps/api/src/server.ts"
echo
echo "Then open:"
echo "  http://127.0.0.1:3001/dashboard"
echo "  http://127.0.0.1:3001/activity"
