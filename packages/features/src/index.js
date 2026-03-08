const CERTAINTY_WORDS = ['clearly', 'obviously', 'definitely', 'undoubtedly', 'everyone knows'];
const HEDGE_WORDS = ['maybe', 'perhaps', 'might', 'seems', 'likely'];
const EMPATHY_WORDS = ['i understand', 'that must be hard', 'it makes sense'];
const CONSENSUS_WORDS = ['everyone knows', 'nobody can trust', 'the whole thing', 'all sides'];

function countMatches(text, patterns) {
  const lower = text.toLowerCase();
  return patterns.reduce((sum, p) => sum + (lower.includes(p) ? 1 : 0), 0);
}

function tokenize(text) {
  return text.toLowerCase().split(/[^a-z0-9']+/).filter(Boolean);
}

export function extractContentFeatures(post) {
  const text = `${post.title || ''} ${post.body || ''}`.trim();
  const tokens = tokenize(text);
  const unique = new Set(tokens);
  const sentences = text.split(/[.!?]+/).map((s) => s.trim()).filter(Boolean);
  const sentenceLengths = sentences.map((s) => tokenize(s).length);
  const meanSentenceLength = sentenceLengths.length
    ? sentenceLengths.reduce((a, b) => a + b, 0) / sentenceLengths.length
    : 0;

  return {
    id: post.id,
    subreddit: post.subreddit,
    token_count: tokens.length,
    sentence_count: sentences.length,
    lexical_diversity: tokens.length ? unique.size / tokens.length : 0,
    certainty_marker_count: countMatches(text, CERTAINTY_WORDS),
    hedging_marker_count: countMatches(text, HEDGE_WORDS),
    empathy_marker_count: countMatches(text, EMPATHY_WORDS),
    consensus_marker_count: countMatches(text, CONSENSUS_WORDS),
    self_reference_count: (text.match(/\b(i|me|my|mine)\b/gi) || []).length,
    exclamation_count: (text.match(/!/g) || []).length,
    question_count: (text.match(/\?/g) || []).length,
    mean_sentence_length: Number(meanSentenceLength.toFixed(2)),
    abstraction_hint: countMatches(text, ['system', 'structure', 'narrative', 'context', 'coordinated', 'manipulated', 'compromised'])
  };
}
