import { detectNarratives } from '../../narratives/src/index.js';

function avg(values) {
  if (!values.length) return 0;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

export function detectClusters(posts = [], analyses = []) {
  const narratives = detectNarratives(posts);
  const scoreMap = new Map(analyses.map((a) => [a.id, a]));

  return narratives.map((nar, index) => {
    const items = nar.post_ids.map((id) => scoreMap.get(id)).filter(Boolean);
    const avgSynthetic = avg(items.map((x) => x.score?.synthetic_language_likelihood || 0));
    const avgSteering = avg(items.map((x) => x.score?.narrative_steering_likelihood || 0));
    const avgCoordination = avg(items.map((x) => x.score?.coordination_likelihood || 0));

    return {
      id: `clu-${index + 1}`,
      narrative_id: nar.id,
      label: nar.label,
      keywords: nar.keywords,
      post_ids: nar.post_ids,
      authors: nar.authors,
      subreddits: nar.subreddits,
      size: nar.count,
      average_synthetic_language_likelihood: round2(avgSynthetic),
      average_narrative_steering_likelihood: round2(avgSteering),
      average_coordination_likelihood: round2(avgCoordination),
      suspicion_rank: round2((avgSynthetic + avgSteering + avgCoordination) / 3)
    };
  }).sort((a, b) => b.suspicion_rank - a.suspicion_rank || b.size - a.size);
}
