#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/projects/truth-lens"
FP_DIR="$ROOT/packages/fingerprints/src"
FP_FILE="$FP_DIR/index.js"
SERVER_FILE="$ROOT/apps/api/src/server.ts"
DASH_FILE="$ROOT/packages/dashboard/src/index.js"

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
    echo "[backup] $file"
  fi
}

mkdir -p "$FP_DIR"

cat > "$FP_FILE" <<'EOF'
import { buildAlerts } from '../../news/src/index.js';
import { buildOutbreaks } from '../../outbreak/src/index.js';
import { buildSignatures } from '../../signatures/src/index.js';
import { buildTraces } from '../../tracing/src/index.js';

function round2(n) {
  return Math.round(n * 100) / 100;
}

function clamp(n, min = 0, max = 1) {
  return Math.max(min, Math.min(max, n));
}

function confidenceBand(score) {
  if (score >= 0.75) return 'high';
  if (score >= 0.45) return 'medium';
  return 'low';
}

function scoreFromAlert(alert) {
  return clamp(alert?.score || 0);
}

function scoreFromOutbreak(outbreak) {
  return clamp(outbreak?.score || 0);
}

function scoreFromSignature(signature) {
  if (!signature) return 0;
  const postScore = clamp((signature.post_count || 0) / 8);
  const authorScore = clamp((signature.author_count || 0) / 5);
  const subredditScore = clamp((signature.subreddit_count || 0) / 4);
  return round2(postScore * 0.5 + authorScore * 0.3 + subredditScore * 0.2);
}

function scoreFromTrace(trace) {
  if (!trace) return 0;
  const subs = clamp((trace.metrics?.total_subreddits || 0) / 4);
  const posts = clamp((trace.metrics?.total_posts || 0) / 8);
  const span = trace.metrics?.span_minutes || 0;
  const compression =
    span <= 15 ? 1 :
    span <= 30 ? 0.8 :
    span <= 60 ? 0.5 :
    span <= 120 ? 0.25 : 0.1;
  return round2(subs * 0.4 + posts * 0.35 + compression * 0.25);
}

export function buildFingerprints(posts = [], analyses = []) {
  const alerts = buildAlerts(posts, analyses);
  const outbreaks = buildOutbreaks(posts, analyses);
  const signatures = buildSignatures(posts, analyses);
  const traces = buildTraces(posts);

  const alertByNarrative = new Map(alerts.map((a) => [a.narrative_id, a]));
  const outbreakByNarrative = new Map(outbreaks.map((o) => [o.narrative_id, o]));
  const traceByNarrative = new Map(traces.map((t) => [t.narrative_id, t]));

  const fingerprints = signatures.map((sig, idx) => {
    const narrativeMatches = [];

    for (const narrativeId of [...alertByNarrative.keys()]) {
      const alert = alertByNarrative.get(narrativeId);
      const outbreak = outbreakByNarrative.get(narrativeId);
      const trace = traceByNarrative.get(narrativeId);

      const sigTerms = new Set((sig.top_terms || []).map(String));
      const alertTerms = new Set(String(alert?.label || '').toLowerCase().split(/[^a-z0-9]+/).filter(Boolean));

      let overlap = 0;
      for (const t of sigTerms) {
        if (alertTerms.has(t)) overlap += 1;
      }

      if (
        overlap >= 1 ||
        (trace?.seed_subreddits || []).some((s) => (sig.subreddits || []).includes(s)) ||
        (trace?.amplifier_subreddits || []).some((s) => (sig.subreddits || []).includes(s))
      ) {
        narrativeMatches.push(narrativeId);
      }
    }

    const linkedAlerts = narrativeMatches.map((id) => alertByNarrative.get(id)).filter(Boolean);
    const linkedOutbreaks = narrativeMatches.map((id) => outbreakByNarrative.get(id)).filter(Boolean);
    const linkedTraces = narrativeMatches.map((id) => traceByNarrative.get(id)).filter(Boolean);

    const maxAlert = linkedAlerts.reduce((m, x) => Math.max(m, scoreFromAlert(x)), 0);
    const maxOutbreak = linkedOutbreaks.reduce((m, x) => Math.max(m, scoreFromOutbreak(x)), 0);
    const maxTrace = linkedTraces.reduce((m, x) => Math.max(m, scoreFromTrace(x)), 0);
    const sigScore = scoreFromSignature(sig);

    const score = round2(
      sigScore * 0.35 +
      maxAlert * 0.2 +
      maxOutbreak * 0.25 +
      maxTrace * 0.2
    );

    return {
      id: `fp-${idx + 1}`,
      label: sig.label,
      confidence: confidenceBand(score),
      score,
      linked_narratives: narrativeMatches,
      signature_id: sig.id,
      post_ids: sig.post_ids,
      authors: sig.authors,
      subreddits: sig.subreddits,
      top_terms: sig.top_terms,
      components: {
        signature_score: sigScore,
        alert_score: maxAlert,
        outbreak_score: maxOutbreak,
        trace_score: maxTrace
      },
      signature: sig.signature
    };
  });

  const rank = { high: 3, medium: 2, low: 1 };
  return fingerprints.sort((a, b) => rank[b.confidence] - rank[a.confidence] || b.score - a.score);
}

export function getFingerprintById(id, posts = [], analyses = []) {
  return buildFingerprints(posts, analyses).find((x) => x.id === id) || null;
}
EOF

echo "[write] $FP_FILE"

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

const fpImport = "import { buildFingerprints, getFingerprintById } from '../../../packages/fingerprints/src/index.js';";
if (!server.includes(fpImport)) {
  const anchor = "import { renderDashboard, renderClusterDetail, renderNarrativeDetail } from '../../../packages/dashboard/src/index.js';";
  if (server.includes(anchor)) {
    server = server.replace(anchor, anchor + "\n" + fpImport);
    console.log("[patched] server fingerprints import");
  } else {
    console.log("[warn] server import anchor not found");
  }
}

const fpRoutes = `  if (url.pathname === '/fingerprints') {
    return json(res, 200, buildFingerprints(listPosts(), listAnalysis()));
  }

  if (parts[0] === 'fingerprints' && parts[1]) {
    const item = getFingerprintById(parts[1], listPosts(), listAnalysis());
    return item ? json(res, 200, item) : notFound(res);
  }

`;
if (!server.includes("if (url.pathname === '/fingerprints')")) {
  const anchor = "  if (url.pathname === '/traces') {";
  if (server.includes(anchor)) {
    server = server.replace(anchor, fpRoutes + anchor);
    console.log("[patched] /fingerprints routes");
  } else {
    const fallbackAnchor = "  if (url.pathname === '/signatures') {";
    if (server.includes(fallbackAnchor)) {
      server = server.replace(fallbackAnchor, fpRoutes + fallbackAnchor);
      console.log("[patched] /fingerprints routes before signatures");
    } else {
      console.log("[warn] fingerprints route anchor not found");
    }
  }
}

const payloadNeedle = "      traces: buildTraces(posts)";
if (!server.includes("fingerprints: buildFingerprints(posts, analyses)")) {
  if (server.includes(payloadNeedle)) {
    server = server.replace(
      payloadNeedle,
      payloadNeedle + ",\n      fingerprints: buildFingerprints(posts, analyses)"
    );
    console.log("[patched] dashboard fingerprints payload");
  } else {
    console.log("[warn] dashboard payload anchor not found");
  }
}

if (!server.includes("'/fingerprints'")) {
  const routeAnchor = "      '/traces',\n      '/traces/:id',";
  if (server.includes(routeAnchor)) {
    server = server.replace(
      routeAnchor,
      routeAnchor + "\n      '/fingerprints',\n      '/fingerprints/:id',"
    );
    console.log("[patched] fallback fingerprints routes");
  } else {
    console.log("[warn] fallback route anchor not found");
  }
}

fs.writeFileSync(serverFile, server);

if (!dash.includes("const fingerprints = data.fingerprints || [];")) {
  const anchor = "  const traces = data.traces || [];";
  if (dash.includes(anchor)) {
    dash = dash.replace(anchor, anchor + "\n  const fingerprints = data.fingerprints || [];");
    console.log("[patched] dashboard fingerprints local");
  } else {
    console.log("[warn] dashboard fingerprints local anchor not found");
  }
}

const fpBlock = `  const fingerprintsHtml = list(fingerprints.slice(0, 5).map((f) => {
    return \`<strong>\${esc(f.label || f.id)}</strong><br><span>confidence=\${esc(f.confidence)} score=\${esc(f.score)}</span><br><span class="muted">\${esc((f.top_terms || []).join(' • '))}</span>\`;
  }));

`;
if (!dash.includes("const fingerprintsHtml = list(fingerprints.slice(0, 5).map((f) => {")) {
  const anchor = "  const summaryHtml = `";
  if (dash.includes(anchor)) {
    dash = dash.replace(anchor, fpBlock + anchor);
    console.log("[patched] fingerprintsHtml block");
  } else {
    console.log("[warn] dashboard summary anchor not found");
  }
}

const oldCards = "  ${card('PRO TIP', proTipHtml)}\n  ${card('NEWS', newsHtml)}\n  ${card('OUTBREAKS', outbreaksHtml)}\n  ${card('SIGNATURE CLUSTERS', signaturesHtml)}\n  ${card('INFLUENCE PATHS', tracesHtml)}\n  ${card('Summary', summaryHtml)}";
const newCards = "  ${card('PRO TIP', proTipHtml)}\n  ${card('NEWS', newsHtml)}\n  ${card('OUTBREAKS', outbreaksHtml)}\n  ${card('SIGNATURE CLUSTERS', signaturesHtml)}\n  ${card('INFLUENCE PATHS', tracesHtml)}\n  ${card('FINGERPRINT ENGINE', fingerprintsHtml)}\n  ${card('Summary', summaryHtml)}";
if (!dash.includes("${card('FINGERPRINT ENGINE', fingerprintsHtml)}")) {
  if (dash.includes(oldCards)) {
    dash = dash.replace(oldCards, newCards);
    console.log("[patched] FINGERPRINT ENGINE card");
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
echo "  http://127.0.0.1:3001/fingerprints"
echo "  http://127.0.0.1:3001/dashboard"
