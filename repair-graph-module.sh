#!/data/data/com.termux/files/usr/bin/bash
set -e

FILE="$HOME/projects/truth-lens/packages/graphfull/src/index.js"

echo "[repairing graph module]"

cp "$FILE" "$FILE.bak.$(date +%s)" 2>/dev/null || true

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

  const nodes = []
  const edges = []

  for (const n of narratives) {
    nodes.push({
      id: n.id,
      type: "narrative",
      label: n.label
    })
  }

  return { nodes, edges }
}

export function renderFullGraphPage(graph) {

  const nodes = graph.nodes || []

  let list = ""

  for (const n of nodes) {
    list += "<li><b>" + n.type + "</b> — " + n.label + "</li>"
  }

  return "<!doctype html>" +
  "<html>" +
  "<head>" +
  "<meta charset='utf-8'>" +
  "<title>Truth Lens Graph</title>" +
  "<style>" +
  "body{font-family:system-ui;background:#0b1020;color:#e8ecf1;padding:20px}" +
  "</style>" +
  "</head>" +
  "<body>" +
  "<h1>Truth Lens Graph</h1>" +
  "<ul>" + list + "</ul>" +
  "</body>" +
  "</html>"
}
EOF

echo "[graph module repaired]"
