#!/data/data/com.termux/files/usr/bin/bash
set -e

ROOT="$HOME/projects/truth-lens"
PRISM_DIR="$ROOT/packages/prism/src"
SERVER="$ROOT/apps/api/src/server.ts"

mkdir -p "$PRISM_DIR"

echo "[creating prism module]"

cat > "$PRISM_DIR/index.js" <<'EOF'
function countMatches(text, words) {
  let score = 0
  for (const w of words) {
    if (text.includes(w)) score++
  }
  return score
}

export function buildPrismProfile(text = "") {

  const lower = text.toLowerCase()

  const factual = countMatches(lower, [
    "data","study","evidence","report","measured","statistics"
  ])

  const narrative = countMatches(lower, [
    "feel","story","fear","hope","anger","identity"
  ])

  const historical = countMatches(lower, [
    "history","tradition","ancient","pattern","before"
  ])

  const systemic = countMatches(lower, [
    "system","framework","structure","model","mechanism"
  ])

  const consensual = countMatches(lower, [
    "experts","researchers","scientists","scholars","consensus"
  ])

  const embodied = countMatches(lower, [
    "body","experience","lived","felt","seen","heard"
  ])

  const emergent = countMatches(lower, [
    "emerge","emergent","new pattern","unexpected","arise"
  ])

  return {
    factual,
    narrative,
    historical,
    systemic,
    consensual,
    embodied,
    emergent
  }
}

export function scorePrism(profile) {

  const values = Object.values(profile)

  const total = values.reduce((a,b)=>a+b,0)

  const active = values.filter(v=>v>0).length

  const coherence = active / 7

  return {
    profile,
    total_signals: total,
    active_registers: active,
    coherence_score: coherence
  }
}
EOF

echo "[patching API]"

cp "$SERVER" "$SERVER.bak.$(date +%s)"

node <<'NODE'
const fs=require("fs")
const path=process.env.HOME+"/projects/truth-lens/apps/api/src/server.ts"

let code=fs.readFileSync(path,"utf8")

if(!code.includes("buildPrismProfile")){

const importLine =
"import { buildPrismProfile, scorePrism } from '../../../packages/prism/src/index.js';\n"

code = importLine + code

const route=`
  if (url.pathname === '/prism') {
    const posts=listPosts()
    const results=posts.map(p=>{
      const profile=buildPrismProfile(p.text||"")
      return {
        id:p.id,
        prism:scorePrism(profile)
      }
    })
    return json(res,200,results)
  }
`

code=code.replace(
"if (url.pathname === '/analysis') {",
route+"\n  if (url.pathname === '/analysis') {"
)

fs.writeFileSync(path,code)

}

NODE

echo
echo "Prism module installed."
echo
echo "Restart API:"
echo "node apps/api/src/server.ts"
echo
echo "Then open:"
echo "http://127.0.0.1:3001/prism"
