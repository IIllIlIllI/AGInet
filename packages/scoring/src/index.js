export function scoreContent(post, features) {
  let synthetic = 0;
  let steering = 0;
  let coordination = 0;
  const reasons = [];

  if (features.lexical_diversity < 0.72) {
    synthetic += 0.12;
    reasons.push('lower lexical diversity');
  }

  if (features.mean_sentence_length > 12) {
    synthetic += 0.1;
    reasons.push('long polished sentences');
  }

  if (features.certainty_marker_count > 0) {
    steering += 0.2;
    reasons.push('certainty markers');
  }

  if (features.consensus_marker_count > 0) {
    steering += 0.25;
    coordination += 0.15;
    reasons.push('consensus framing');
  }

  if (features.abstraction_hint > 1) {
    synthetic += 0.12;
    steering += 0.12;
    reasons.push('abstraction-heavy language');
  }

  if (features.exclamation_count > 1) {
    steering += 0.08;
    reasons.push('elevated emotional punctuation');
  }

  synthetic = clamp(synthetic + 0.18);
  steering = clamp(steering + 0.12);
  coordination = clamp(coordination + 0.1);

  const confidence = clamp(0.25 + (features.token_count > 12 ? 0.2 : 0) + (reasons.length * 0.08));

  return {
    id: post.id,
    entity_type: 'content',
    synthetic_language_likelihood: round2(synthetic),
    narrative_steering_likelihood: round2(steering),
    coordination_likelihood: round2(coordination),
    confidence: round2(confidence),
    confidence_band: band(confidence),
    reasons: Array.from(new Set(reasons))
  };
}

function clamp(n) {
  return Math.max(0, Math.min(1, n));
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

function band(n) {
  if (n < 0.2) return 'very_low';
  if (n < 0.4) return 'low';
  if (n < 0.6) return 'moderate';
  if (n < 0.8) return 'high';
  return 'very_high';
}
