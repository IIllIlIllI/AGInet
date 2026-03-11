function avg(values) {
  if (!values.length) return 0;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function round3(n) {
  return Math.round(n * 1000) / 1000;
}

function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

const STOP = new Set([
  'the','and','but','or','if','then','because','that','which','to','of','in','a','an',
  'is','are','it','this','we','they','you','for','with','was','were','be','as','on','at'
]);

function topKeywords(post, max = 8) {
  const counts = new Map();
  const tokens = tokenize(`${post.title || ''} ${post.body || ''}`);
  for (const t of tokens) {
    if (STOP.has(t) || t.length < 4) continue;
    counts.set(t, (counts.get(t) || 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, max)
    .map(([k]) => k);
}

export function buildBaselines(posts = [], analyses = []) {
  const bySub = new Map();
  const analysisMap = new Map(analyses.map((a) => [a.id, a]));

  for (const post of posts) {
    const sub = post.subreddit || 'unknown';
    if (!bySub.has(sub)) bySub.set(sub, []);
    const analysis = analysisMap.get(post.id);
    if (analysis) bySub.get(sub).push({ post, analysis });
  }

  const out = [];

  for (const [subreddit, rows] of bySub.entries()) {
    const keywordCounts = new Map();

    for (const row of rows) {
      for (const k of topKeywords(row.post)) {
        keywordCounts.set(k, (keywordCounts.get(k) || 0) + 1);
      }
    }

    const common_keywords = [...keywordCounts.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 12)
      .map(([keyword, count]) => ({ keyword, count }));

    out.push({
      subreddit,
      post_count: rows.length,
      average_synthetic_language_likelihood: round3(avg(rows.map((r) => r.analysis.score?.synthetic_language_likelihood || 0))),
      average_narrative_steering_likelihood: round3(avg(rows.map((r) => r.analysis.score?.narrative_steering_likelihood || 0))),
      average_coordination_likelihood: round3(avg(rows.map((r) => r.analysis.score?.coordination_likelihood || 0))),
      average_token_count: round3(avg(rows.map((r) => r.analysis.features?.token_count || 0))),
      average_lexical_diversity: round3(avg(rows.map((r) => r.analysis.features?.lexical_diversity || 0))),
      average_sentence_length_variance: round3(avg(rows.map((r) => r.analysis.features?.sentence_length_variance || 0))),
      average_function_word_ratio: round3(avg(rows.map((r) => r.analysis.features?.function_word_ratio || 0))),
      common_keywords
    });
  }

  return out.sort((a, b) => a.subreddit.localeCompare(b.subreddit));
}

export function getBaselineForSubreddit(subreddit, posts = [], analyses = []) {
  return buildBaselines(posts, analyses).find((x) => x.subreddit === subreddit) || null;
}

export function compareClusterToBaselines(cluster, baselines = []) {
  const matches = (cluster.subreddits || [])
    .map((sub) => baselines.find((b) => b.subreddit === sub))
    .filter(Boolean);

  if (!matches.length) {
    return {
      baseline_context: 'no baseline available',
      steering_delta: 0,
      coordination_delta: 0,
      synthetic_delta: 0
    };
  }

  const avgSynthetic = avg(matches.map((m) => m.average_synthetic_language_likelihood || 0));
  const avgSteering = avg(matches.map((m) => m.average_narrative_steering_likelihood || 0));
  const avgCoordination = avg(matches.map((m) => m.average_coordination_likelihood || 0));

  return {
    baseline_context: `compared against ${matches.length} subreddit baseline(s)`,
    steering_delta: round3((cluster.average_narrative_steering_likelihood || 0) - avgSteering),
    coordination_delta: round3((cluster.average_coordination_likelihood || 0) - avgCoordination),
    synthetic_delta: round3((cluster.average_synthetic_language_likelihood || 0) - avgSynthetic)
  };
}
