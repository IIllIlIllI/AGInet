#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/projects/truth-lens"
GRAPH_DIR="$ROOT/packages/graphfull/src"
GRAPH_FILE="$GRAPH_DIR/index.js"
SERVER_FILE="$ROOT/apps/api/src/server.ts"
DASH_FILE="$ROOT/packages/dashboard/src/index.js"

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
    echo "[backup] $file"
  fi
}

mkdir -p "$GRAPH_DIR"

cat > "$GRAPH_FILE" <<'EOF'
import { detectNarratives } from '../../narratives/src/index.js';
import { buildSignatures } from '../../signatures/src/index.js';
import { buildTraces } from '../../tracing/src/index.js';
import { buildFingerprints } from '../../fingerprints/src/index.js';

function esc(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function buildFullGraph(posts = [], analyses = []) {
  const narratives = detectNarratives(posts);
  const signatures = buildSignatures(posts, analyses);
  const traces = buildTraces(posts);
  const fingerprints = buildFingerprints(posts, analyses);

  const nodes = [];
  const edges = [];
  const nodeIds = new Set();

  function pushNode(node) {
    if (nodeIds.has(node.id)) return;
    nodeIds.add(node.id);
    nodes.push(node);
  }

  for (const n of narratives) {
    pushNode({
      id: n.id,
      type: 'narrative',
      label: n.label,
      size: n.count || n.post_ids?.length || 0
    });
  }

  for (const s of signatures) {
    pushNode({
      id: s.id,
      type: 'signature',
      label: s.label,
      size: s.post_count || 0
    });
  }

  for (const t of traces) {
    pushNode({
      id: t.id,
      type: 'trace',
      label: t.label,
      size: t.metrics?.total_posts || 0
    });
  }

  for (const f of fingerprints) {
    pushNode({
      id: f.id,
      type: 'fingerprint',
      label: f.label,
      size: f.post_ids?.length || 0,
      confidence: f.confidence
    });
  }

  for (const f of fingerprints) {
    if (f.signature_id) {
      edges.push({ source: f.id, target: f.signature_id, type: 'fingerprint_to_signature' });
    }
    for (const narrativeId of f.linked_narratives || []) {
      edges.push({ source: f.id, target: narrativeId, type: 'fingerprint_to_narrative' });
    }
  }

  for (const t of traces) {
    if (t.narrative_id) {
      edges.push({ source: t.id, target: t.narrative_id, type: 'trace_to_narrative' });
    }
  }

  for (const s of signatures) {
    const sigTerms = new Set((s.top_terms || []).map((x) => String(x).toLowerCase()));
    for (const n of narratives) {
      const nTerms = new Set((n.keywords || []).map((x) => String(x).toLowerCase()));
      let overlap = 0;
      for (const term of sigTerms) {
        if (nTerms.has(term)) overlap += 1;
      }
      if (overlap >= 1) {
        edges.push({ source: s.id, target: n.id, type: 'signature_to_narrative' });
      }
    }
  }

  return { nodes, edges };
}

export function renderFullGraphPage(graph) {
  const nodes = graph.nodes || [];
  const edges = graph.edges || [];

  const columns = {
    fingerprint: 160,
    signature: 460,
    narrative: 800,
    trace: 1120
  };

  const byType = {
    fingerprint: nodes.filter((n) => n.type === 'fingerprint'),
    signature: nodes.filter((n) => n.type === 'signature'),
    narrative: nodes.filter((n) => n.type === 'narrative'),
    trace: nodes.filter((n) => n.type === 'trace')
  };

  const rowGap = 90;
  const topPad = 90;
  const width = 1400;
  const maxRows = Math.max(
    byType.fingerprint.length,
    byType.signature.length,
    byType.narrative.length,
    byType.trace.length,
    1
  );
  const height = Math.max(760, topPad + maxRows * rowGap + 120);

  const positioned = new Map();

  for (const [type, list] of Object.entries(byType)) {
    list.forEach((node, i) => {
      positioned.set(node.id, {
        ...node,
        x: columns[type],
        y: topPad + i * rowGap
      });
    });
  }

  function color(type) {
    if (type === 'fingerprint') return '#ff9aa2';
    if (type === 'signature') return '#ffb86b';
    if (type === 'narrative') return '#8ec5ff';
    if (type === 'trace') return '#7ee787';
    return '#c9d1d9';
  }

  function href(node) {
    if (node.type === 'narrative') return `/narratives/${encodeURIComponent(node.id)}`;
    if (node.type === 'signature') return `/signatures/${encodeURIComponent(node.id)}`;
    if (node.type === 'fingerprint') return `/fingerprints/${encodeURIComponent(node.id)}`;
    if (node.type === 'trace') return `/traces/${encodeURIComponent(node.id)}`;
    return null;
  }

  const edgeSvg = edges.map((e) => {
    const a = positioned.get(e.source);
    const b = positioned.get(e.target);
    if (!a || !b) return '';
    return `<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="#395178" stroke-width="1.5" opacity="0.75" />`;
  }).join('');

  const nodeSvg = [...positioned.values()].map((n) => {
    const fill = color(n.type);
    const label = esc(n.label || n.id).slice(0, 42);
    const link = href(n);
    const body = `<g><circle cx="${n.x}" cy="${n.y}" r="16" fill="${fill}" stroke="#0b1020" stroke-width="2" /><text x="${n.x + 24}" y="${n.y + 5}" fill="#e8ecf1" font-size="13">${label}</text></g>`;
    return link ? `<a href="${link}">${body}</a>` : body;
  }).join('');

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Truth Lens Full Graph</title>
  <style>
    body{font-family:system-ui,sans-serif;margin:0;padding:16px;background:#0b1020;color:#e8ecf1}
    .card{background:#121a2b;border:1px solid #25314a;border-radius:14px;padding:14px;margin-bottom:14px}
    a{color:#8ec5ff}
    .muted{color:#9aa4b2}
    .legend{display:flex;gap:16px;flex-wrap:wrap}
    .legend span{display:inline-flex;align-items:center;gap:6px}
    .dot{width:12px;height:12px;border-radius:50%;display:inline-block}
  </style>
</head>
<body>
  <p><a href="/dashboard">← Back to dashboard</a></p>
  <div class="card">
    <h1>Truth Lens Full Graph</h1>
    <p class="muted">Deterministic graph view connecting fingerprints, signatures, narratives, and traces.</p>
    <div class="legend">
      <span><i class="dot" style="background:#ff9aa2"></i>Fingerprints</span>
      <span><i class="dot" style="background:#ffb86b"></i>Signatures</span>
      <span><i class="dot" style="background:#8ec5ff"></i>Narratives</span>
      <span><i class="dot" style="background:#7ee787"></i>Traces</span>
    </div>
  </div>
  <div class="card">
    <svg width="100%" viewBox="0 0 ${width} ${height}" preserveAspectRatio="xMinYMin meet">
      <text x="80" y="40" fill="#9aa4b2" font-size="16">Fingerprints</text>
      <text x="380" y="40" fill="#9aa4b2" font-size="16">Signatures</text>
      <text x="730" y="40" fill="#9aa4b2" font-size="16">Narratives</text>
      <text x="1070" y="40" fill="#9aa4b2" font-size="16">Traces</text>
      ${edgeSvg}
      ${nodeSvg}
    </svg>
  </div>
</body>
</html>`;
}
EOF

echo "[write] $GRAPH_FILE"

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

const graphImport = "import { buildFullGraph, renderFullGraphPage } from '../../../packages/graphfull/src/index.js';";
if (!server.includes(graphImport)) {
  const anchor = "import { renderDashboard, renderClusterDetail, renderNarrativeDetail } from '../../../packages/dashboard/src/index.js';";
  if (server.includes(anchor)) {
    server = server.replace(anchor, anchor + "\n" + graphImport);
    console.log("[patched] server graph import");
  } else {
    console.log("[warn] server import anchor not found");
  }
}

const graphRoutes = `  if (url.pathname === '/graph/full') {
    return json(res, 200, buildFullGraph(listPosts(), listAnalysis()));
  }

  if (url.pathname === '/dashboard/graph-full') {
    return html(res, 200, renderFullGraphPage(buildFullGraph(listPosts(), listAnalysis())));
  }

`;
if (!server.includes("if (url.pathname === '/graph/full')")) {
  const anchor = "  if (url.pathname === '/fingerprints') {";
  if (server.includes(anchor)) {
    server = server.replace(anchor, graphRoutes + anchor);
    console.log("[patched] graph routes");
  } else {
    const fallbackAnchor = "  if (url.pathname === '/traces') {";
    if (server.includes(fallbackAnchor)) {
      server = server.replace(fallbackAnchor, graphRoutes + fallbackAnchor);
      console.log("[patched] graph routes before traces");
    } else {
      console.log("[warn] graph route anchor not found");
    }
  }
}

if (!server.includes("'/graph/full'")) {
  const routeAnchor = "      '/fingerprints',\n      '/fingerprints/:id',";
  if (server.includes(routeAnchor)) {
    server = server.replace(
      routeAnchor,
      routeAnchor + "\n      '/graph/full',\n      '/dashboard/graph-full',"
    );
    console.log("[patched] fallback graph routes");
  } else {
    console.log("[warn] fallback route anchor not found");
  }
}

fs.writeFileSync(serverFile, server);

const oldLink = "    '<a href=\"/narratives\">/narratives</a>'";
const newLink = "    '<a href=\"/narratives\">/narratives</a>',\n    '<a href=\"/graph/full\">/graph/full</a>',\n    '<a href=\"/dashboard/graph-full\">/dashboard/graph-full</a>'";
if (!dash.includes('/dashboard/graph-full')) {
  if (dash.includes(oldLink)) {
    dash = dash.replace(oldLink, newLink);
    console.log("[patched] dashboard graph links");
  } else {
    console.log("[warn] dashboard links anchor not found");
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
echo "  http://127.0.0.1:3001/graph/full"
echo "  http://127.0.0.1:3001/dashboard/graph-full"
