#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/projects/truth-lens"
SIG_DIR="$ROOT/packages/signatures/src"
SIG_FILE="$SIG_DIR/index.js"
SERVER_FILE="$ROOT/apps/api/src/server.ts"
DASH_FILE="$ROOT/packages/dashboard/src/index.js"

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
    echo "[backup] $file"
  fi
}

mkdir -p "$SIG_DIR"

cat > "$SIG_FILE" <<'EOF'
function band(value, cuts, labels) {
  for (let i = 0; i < cuts.length; i += 1) {
    if (value < cuts[i]) return labels[i];
  }
  return labels[labels.length - 1];
}

function safeText(post) {
  return `${post.title || ''} ${post.body || ''}`.toLowerCase();
}

function topTerms(text, max = 5) {
  const stop = new Set([
    'the','and','but','or','if','then','because','that','which','to','of','in','a','an',
    'is','are','it','this','we','they','you','for','with','was','were','be','as','on','at'
  ]);

  const counts = new Map();
  for (const token of text.replace(/[^a-z0-9\\s]/g, ' ').split(/\\s+/).filter(Boolean)) {
    if (stop.has(token) || token.length < 4) continue;
    counts.set(token, (counts.get(token) || 0) + 1);
  }

  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, max)
    .map(([k]) => k);
}

function phrasingBand(post) {
  const title = String(post.title || '');
  if (title.includes('?')) return 'interrogative';
  if (/[A-Z]{4,}/.test(title)) return 'emphatic';
  if (title.split(':').length > 1) return 'framed';
  return 'plain';
}

function timingBand(post) {
  const d = new Date(post.created_at || 0);
  if (!Number.isFinite(d.getTime())) return 'unknown';
  const h = d.getUTCHours();
  if (h < 6) return 'overnight';
  if (h < 12) return 'morning';
  if (h < 18) return 'afternoon';
  return 'evening';
}

function buildSignatureKey(post, analysis) {
  const lexical = band(
    analysis?.features?.lexical_diversity || 0,
    [0.25, 0.45, 0.65],
    ['very-low', 'low', 'medium', 'high']
  );

  const variance = band(
    analysis?.features?.sentence_length_variance || 0,
    [3, 8, 16],
    ['flat', 'controlled', 'varied', 'chaotic']
  );

  const functionWord = band(
    analysis?.features?.function_word_ratio || 0,
    [0.25, 0.4, 0.55],
    ['sparse', 'balanced', 'dense', 'very-dense']
  );

  const phrase = phrasingBand(post);
  const time = timingBand(post);

  return {
    key: [lexical, variance, functionWord, phrase, time].join('|'),
    lexical_diversity_band: lexical,
    sentence_variance_band: variance,
    function_word_ratio_band: functionWord,
    phrasing_band: phrase,
    timing_band: time
  };
}

export function buildSignatures(posts = [], analyses = []) {
  const analysisMap = new Map(analyses.map((a) => [a.id, a]));
  const groups = new Map();

  for (const post of posts) {
    const analysis = analysisMap.get(post.id);
    if (!analysis) continue;

    const sig = buildSignatureKey(post, analysis);
    if (!groups.has(sig.key)) {
      groups.set(sig.key, {
        id: `sig-${groups.size + 1}`,
        label: `${sig.lexical_diversity_band} lexical / ${sig.sentence_variance_band} variance / ${sig.phrasing_band}`,
        signature: sig,
        post_ids: [],
        authors: new Set(),
        subreddits: new Set(),
        top_terms: new Map()
      });
    }

    const g = groups.get(sig.key);
    g.post_ids.push(post.id);
    g.authors.add(post.author);
    g.subreddits.add(post.subreddit);

    for (const term of topTerms(safeText(post))) {
      g.top_terms.set(term, (g.top_terms.get(term) || 0) + 1);
    }
  }

  return [...groups.values()]
    .map((g) => ({
      id: g.id,
      label: g.label,
      post_ids: g.post_ids,
      authors: [...g.authors].sort(),
      subreddits: [...g.subreddits].sort(),
      post_count: g.post_ids.length,
      author_count: g.authors.size,
      subreddit_count: g.subreddits.size,
      signature: g.signature,
      top_terms: [...g.top_terms.entries()]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .slice(0, 6)
        .map(([term]) => term)
    }))
    .sort((a, b) => b.post_count - a.post_count || b.author_count - a.author_count || a.label.localeCompare(b.label));
}

export function getSignatureById(id, posts = [], analyses = []) {
  return buildSignatures(posts, analyses).find((x) => x.id === id) || null;
}
EOF

echo "[write] $SIG_FILE"

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

const sigImport = "import { buildSignatures, getSignatureById } from '../../../packages/signatures/src/index.js';";
if (!server.includes(sigImport)) {
  const anchor = "import { renderDashboard, renderClusterDetail, renderNarrativeDetail } from '../../../packages/dashboard/src/index.js';";
  if (server.includes(anchor)) {
    server = server.replace(anchor, anchor + "\n" + sigImport);
    console.log("[patched] server signatures import");
  } else {
    console.log("[warn] server import anchor not found");
  }
}

const sigRoutes = `  if (url.pathname === '/signatures') {
    return json(res, 200, buildSignatures(listPosts(), listAnalysis()));
  }

  if (parts[0] === 'signatures' && parts[1]) {
    const item = getSignatureById(parts[1], listPosts(), listAnalysis());
    return item ? json(res, 200, item) : notFound(res);
  }

`;
if (!server.includes("if (url.pathname === '/signatures')")) {
  const anchor = "  if (url.pathname === '/outbreaks') {";
  if (server.includes(anchor)) {
    server = server.replace(anchor, sigRoutes + anchor);
    console.log("[patched] /signatures routes");
  } else {
    const fallbackAnchor = "  if (url.pathname === '/alerts') {";
    if (server.includes(fallbackAnchor)) {
      server = server.replace(fallbackAnchor, sigRoutes + fallbackAnchor);
      console.log("[patched] /signatures routes before alerts");
    } else {
      console.log("[warn] signatures route anchor not found");
    }
  }
}

const payloadNeedle = "      outbreaks: buildOutbreaks(posts, analyses)";
if (!server.includes("signatures: buildSignatures(posts, analyses)")) {
  if (server.includes(payloadNeedle)) {
    server = server.replace(
      payloadNeedle,
      payloadNeedle + ",\n      signatures: buildSignatures(posts, analyses)"
    );
    console.log("[patched] dashboard signatures payload");
  } else {
    console.log("[warn] dashboard payload anchor not found");
  }
}

if (!server.includes("'/signatures'")) {
  const routeAnchor = "      '/outbreaks',\n      '/outbreaks/:id',";
  if (server.includes(routeAnchor)) {
    server = server.replace(
      routeAnchor,
      routeAnchor + "\n      '/signatures',\n      '/signatures/:id',"
    );
    console.log("[patched] fallback signatures routes");
  } else {
    console.log("[warn] fallback route anchor not found");
  }
}

fs.writeFileSync(serverFile, server);

if (!dash.includes("const signatures = data.signatures || [];")) {
  const anchor = "  const outbreaks = data.outbreaks || [];";
  if (dash.includes(anchor)) {
    dash = dash.replace(anchor, anchor + "\n  const signatures = data.signatures || [];");
    console.log("[patched] dashboard signatures local");
  } else {
    console.log("[warn] dashboard signatures local anchor not found");
  }
}

const sigBlock = `  const signaturesHtml = list(signatures.slice(0, 5).map((s) => {
    return \`<strong>\${esc(s.label || s.id)}</strong><br><span>posts=\${esc(s.post_count)} authors=\${esc(s.author_count)} subreddits=\${esc(s.subreddit_count)}</span><br><span class="muted">\${esc((s.top_terms || []).join(' • '))}</span>\`;
  }));

`;
if (!dash.includes("const signaturesHtml = list(signatures.slice(0, 5).map((s) => {")) {
  const anchor = "  const summaryHtml = `";
  if (dash.includes(anchor)) {
    dash = dash.replace(anchor, sigBlock + anchor);
    console.log("[patched] signaturesHtml block");
  } else {
    console.log("[warn] dashboard summary anchor not found");
  }
}

const oldCards = "  ${card('PRO TIP', proTipHtml)}\n  ${card('NEWS', newsHtml)}\n  ${card('OUTBREAKS', outbreaksHtml)}\n  ${card('Summary', summaryHtml)}";
const newCards = "  ${card('PRO TIP', proTipHtml)}\n  ${card('NEWS', newsHtml)}\n  ${card('OUTBREAKS', outbreaksHtml)}\n  ${card('SIGNATURE CLUSTERS', signaturesHtml)}\n  ${card('Summary', summaryHtml)}";
if (!dash.includes("${card('SIGNATURE CLUSTERS', signaturesHtml)}")) {
  if (dash.includes(oldCards)) {
    dash = dash.replace(oldCards, newCards);
    console.log("[patched] SIGNATURE CLUSTERS card");
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
echo "  http://127.0.0.1:3001/signatures"
echo "  http://127.0.0.1:3001/dashboard"
