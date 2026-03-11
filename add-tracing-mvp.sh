#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/projects/truth-lens"
TRACE_DIR="$ROOT/packages/tracing/src"
TRACE_FILE="$TRACE_DIR/index.js"
SERVER_FILE="$ROOT/apps/api/src/server.ts"
DASH_FILE="$ROOT/packages/dashboard/src/index.js"

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
    echo "[backup] $file"
  fi
}

mkdir -p "$TRACE_DIR"

cat > "$TRACE_FILE" <<'EOF'
import { buildSpread } from '../../spread/src/index.js';

function toMs(v) {
  const n = new Date(v).getTime();
  return Number.isFinite(n) ? n : 0;
}

export function buildTraces(posts = []) {
  const spread = buildSpread(posts);
  const postMap = new Map(posts.map((p) => [p.id, p]));

  return spread.map((item, idx) => {
    const members = (item.post_ids || [])
      .map((id) => postMap.get(id))
      .filter(Boolean)
      .map((p) => ({ ...p, _ts: toMs(p.created_at) }))
      .filter((p) => p._ts > 0)
      .sort((a, b) => a._ts - b._ts);

    const bySubreddit = new Map();
    const earlyAuthors = [];
    const seenAuthors = new Set();

    for (const post of members) {
      if (!bySubreddit.has(post.subreddit)) {
        bySubreddit.set(post.subreddit, {
          subreddit: post.subreddit,
          first_seen: post.created_at,
          post_count: 0,
          authors: new Set()
        });
      }

      const row = bySubreddit.get(post.subreddit);
      row.post_count += 1;
      row.authors.add(post.author);

      if (earlyAuthors.length < 5 && post.author && !seenAuthors.has(post.author)) {
        earlyAuthors.push(post.author);
        seenAuthors.add(post.author);
      }
    }

    const spread_path = [...bySubreddit.values()]
      .map((x) => ({
        subreddit: x.subreddit,
        first_seen: x.first_seen,
        post_count: x.post_count,
        author_count: x.authors.size
      }))
      .sort((a, b) => toMs(a.first_seen) - toMs(b.first_seen));

    const seed_subreddits = spread_path.slice(0, 1).map((x) => x.subreddit);
    const amplifier_subreddits = spread_path
      .slice(1)
      .filter((x) => x.post_count >= 1)
      .map((x) => x.subreddit);

    return {
      id: `trace-${idx + 1}`,
      narrative_id: item.id,
      label: item.label,
      seed_subreddits,
      amplifier_subreddits,
      early_authors: earlyAuthors,
      spread_path,
      metrics: {
        total_posts: item.post_ids.length,
        total_subreddits: item.subreddit_count || 0,
        total_authors: item.author_count || 0,
        span_minutes: item.span_minutes || 0
      }
    };
  }).sort((a, b) => {
    return (b.metrics.total_subreddits - a.metrics.total_subreddits)
      || (b.metrics.total_posts - a.metrics.total_posts)
      || a.label.localeCompare(b.label);
  });
}

export function getTraceById(id, posts = []) {
  return buildTraces(posts).find((x) => x.id === id) || null;
}
EOF

echo "[write] $TRACE_FILE"

backup_file "$SERVER_FILE"
backup_file "$DASH_FILE"

node - <<'NODE'
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(process.env.HOME, 'projects', 'truth-lens');
const serverFile = path.join(root, 'apps/api/src/server.ts');
const dashFile = path.join(root, 'packages/dashboard/src/index.js');

let server = fs.readFileSync(serverFile, 'utf8');
let dash = fs.readFileSync(dashFile, 'utf8');

const traceImport = "import { buildTraces, getTraceById } from '../../../packages/tracing/src/index.js';";
if (!server.includes(traceImport)) {
  const anchor = "import { renderDashboard, renderClusterDetail, renderNarrativeDetail } from '../../../packages/dashboard/src/index.js';";
  if (server.includes(anchor)) {
    server = server.replace(anchor, anchor + "\n" + traceImport);
    console.log("[patched] server tracing import");
  } else {
    console.log("[warn] server import anchor not found");
  }
}

const traceRoutes = `  if (url.pathname === '/traces') {
    return json(res, 200, buildTraces(listPosts()));
  }

  if (parts[0] === 'traces' && parts[1]) {
    const item = getTraceById(parts[1], listPosts());
    return item ? json(res, 200, item) : notFound(res);
  }

`;
if (!server.includes("if (url.pathname === '/traces')")) {
  const anchor = "  if (url.pathname === '/signatures') {";
  if (server.includes(anchor)) {
    server = server.replace(anchor, traceRoutes + anchor);
    console.log("[patched] /traces routes");
  } else {
    const fallbackAnchor = "  if (url.pathname === '/outbreaks') {";
    if (server.includes(fallbackAnchor)) {
      server = server.replace(fallbackAnchor, traceRoutes + fallbackAnchor);
      console.log("[patched] /traces routes before outbreaks");
    } else {
      console.log("[warn] traces route anchor not found");
    }
  }
}

const payloadNeedle = "      signatures: buildSignatures(posts, analyses)";
if (!server.includes("traces: buildTraces(posts)")) {
  if (server.includes(payloadNeedle)) {
    server = server.replace(
      payloadNeedle,
      payloadNeedle + ",\n      traces: buildTraces(posts)"
    );
    console.log("[patched] dashboard traces payload");
  } else {
    console.log("[warn] dashboard payload anchor not found");
  }
}

if (!server.includes("'/traces'")) {
  const routeAnchor = "      '/signatures',\n      '/signatures/:id',";
  if (server.includes(routeAnchor)) {
    server = server.replace(
      routeAnchor,
      routeAnchor + "\n      '/traces',\n      '/traces/:id',"
    );
    console.log("[patched] fallback traces routes");
  } else {
    console.log("[warn] fallback route anchor not found");
  }
}

fs.writeFileSync(serverFile, server);

if (!dash.includes("const traces = data.traces || [];")) {
  const anchor = "  const signatures = data.signatures || [];";
  if (dash.includes(anchor)) {
    dash = dash.replace(anchor, anchor + "\n  const traces = data.traces || [];");
    console.log("[patched] dashboard traces local");
  } else {
    console.log("[warn] dashboard traces local anchor not found");
  }
}

const traceBlock = `  const tracesHtml = list(traces.slice(0, 5).map((t) => {
    return \`<strong>\${esc(t.label || t.id)}</strong><br><span>seed=\${esc((t.seed_subreddits || []).join(', '))}</span><br><span class="muted">amplifiers=\${esc((t.amplifier_subreddits || []).join(' • '))}</span>\`;
  }));

`;
if (!dash.includes("const tracesHtml = list(traces.slice(0, 5).map((t) => {")) {
  const anchor = "  const summaryHtml = `";
  if (dash.includes(anchor)) {
    dash = dash.replace(anchor, traceBlock + anchor);
    console.log("[patched] tracesHtml block");
  } else {
    console.log("[warn] dashboard summary anchor not found");
  }
}

const oldCards = "  ${card('PRO TIP', proTipHtml)}\n  ${card('NEWS', newsHtml)}\n  ${card('OUTBREAKS', outbreaksHtml)}\n  ${card('SIGNATURE CLUSTERS', signaturesHtml)}\n  ${card('Summary', summaryHtml)}";
const newCards = "  ${card('PRO TIP', proTipHtml)}\n  ${card('NEWS', newsHtml)}\n  ${card('OUTBREAKS', outbreaksHtml)}\n  ${card('SIGNATURE CLUSTERS', signaturesHtml)}\n  ${card('INFLUENCE PATHS', tracesHtml)}\n  ${card('Summary', summaryHtml)}";
if (!dash.includes("${card('INFLUENCE PATHS', tracesHtml)}")) {
  if (dash.includes(oldCards)) {
    dash = dash.replace(oldCards, newCards);
    console.log("[patched] INFLUENCE PATHS card");
  } else {
    console.log("[warn] dashboard cards anchor not found");
  }
}

fs.writeFileSync(dashFile, dash);
NODE

echo
echo "Done."
echo "Now run:"
echo "  cd $ROOT"
echo "  node apps/worker/src/worker.ts"
echo "  node apps/api/src/server.ts"
echo
echo "Then open:"
echo "  http://127.0.0.1:3001/traces"
echo "  http://127.0.0.1:3001/dashboard"
