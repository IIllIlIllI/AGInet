#!/data/data/com.termux/files/usr/bin/bash
set -e

FILE="$HOME/projects/truth-lens/packages/graphfull/src/index.js"

cp "$FILE" "$FILE.bak.$(date +%s)"

cat > "$FILE" <<'EOF'
import { detectNarratives } from '../../narratives/src/index.js'

async function safeImport(path) {
  try {
    return await import(path)
  } catch {
    return null
  }
}

export async function buildFullGraph(posts = [], analyses = []) {

  const narratives = detectNarratives(posts)

  const signaturesMod = await safeImport('../../signatures/src/index.js')
  const tracesMod = await safeImport('../../tracing/src/index.js')
  const fingerprintsMod = await safeImport('../../fingerprints/src/index.js')

  const signatures = signaturesMod?.buildSignatures
    ? signaturesMod.buildSignatures(posts, analyses)
    : []

  const traces = tracesMod?.buildTraces
    ? tracesMod.buildTraces(posts)
    : []

  const fingerprints = fingerprintsMod?.buildFingerprints
    ? fingerprintsMod.buildFingerprints(posts, analyses)
    : []

  const nodes = []
  const edges = []

  for (const n of narratives) {
    nodes.push({
      id: n.id,
      type: "narrative",
      label: n.label
    })
  }

  for (const s of signatures) {
    nodes.push({
      id: s.id,
      type: "signature",
      label: s.label
    })
  }

  for (const t of traces) {
    nodes.push({
      id: t.id,
      type: "trace",
      label: t.label
    })
  }

  for (const f of fingerprints) {
    nodes.push({
      id: f.id,
      type: "fingerprint",
      label: f.label
    })
  }

  return { nodes, edges }
}

export function renderFullGraphPage(graph) {

  const nodes = graph.nodes || []

  const items = nodes.map(n =>
    `<li><b>${n.type}</b> — ${n.label}</li>`
  ).join("")

  return \`
  <!doctype html>
  <html>
  <head>
  <meta charset="utf-8">
  <title>Truth Lens Graph</title>
  <style>
  body{font-family:system-ui;background:#0b1020;color:#e8ecf1;padding:16px}
  </style>
  </head>
  <body>
  <h1>Truth Lens Graph</h1>
  <ul>\${items}</ul>
  </body>
  </html>
  \`
}
EOF

echo "[patched] graph module safe imports"
