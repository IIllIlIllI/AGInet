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
