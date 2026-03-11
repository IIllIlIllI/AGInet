import { detectClusters } from '../../cluster/src/index.js';
import { buildBaselines, compareClusterToBaselines } from '../../baseline/src/index.js';

function round2(n) {
  return Math.round(n * 100) / 100;
}

function clamp(n, min = 0, max = 1) {
  return Math.max(min, Math.min(max, n));
}

function stateFromScore(score) {
  if (score >= 0.8) return 'severe';
  if (score >= 0.55) return 'outbreak';
  if (score >= 0.3) return 'watch';
  return 'observe';
}

function toMs(v) {
  const n = new Date(v).getTime();
  return Number.isFinite(n) ? n : 0;
}

function minutesBetween(minTs, maxTs) {
  if (!minTs || !maxTs || maxTs < minTs) return 0;
  return round2((maxTs - minTs) / 60000);
}

function scoreGrowth(currentCount, previousCount) {
  if (currentCount <= 0) return 0;
  const ratio = currentCount / Math.max(1, previousCount);
  if (ratio >= 4) return 1;
  if (ratio >= 3) return 0.8;
  if (ratio >= 2) return 0.6;
  if (ratio >= 1.5) return 0.4;
  return clamp((currentCount - 1) / 5);
}

function scoreAuthors(authorCount) {
  return clamp((authorCount - 1) / 4);
}

function scoreSubreddits(subredditCount) {
  return clamp((subredditCount - 1) / 3);
}

function scoreCompression(spanMinutes, currentCount) {
  if (currentCount < 2) return 0;
  if (spanMinutes <= 10) return 1;
  if (spanMinutes <= 20) return 0.8;
  if (spanMinutes <= 40) return 0.6;
  if (spanMinutes <= 60) return 0.35;
  return 0.1;
}

function scoreBaselineDelta(delta) {
  return clamp((delta || 0) / 0.3);
}

export function buildOutbreaks(posts = [], analyses = []) {
  const baselines = buildBaselines(posts, analyses);
  const clusters = detectClusters(posts, analyses).map((cluster) => ({
    ...cluster,
    baseline: compareClusterToBaselines(cluster, baselines)
  }));
  const postMap = new Map(posts.map((p) => [p.id, p]));
  const now = Date.now();
  const currentWindowMs = 15 * 60 * 1000;
  const previousWindowMs = 60 * 60 * 1000;

  const outbreaks = clusters.map((cluster, idx) => {
    const members = (cluster.post_ids || [])
      .map((id) => postMap.get(id))
      .filter(Boolean)
      .map((p) => ({ ...p, _ts: toMs(p.created_at) }))
      .filter((p) => p._ts > 0);

    const current = members.filter((p) => now - p._ts <= currentWindowMs);
    const previous = members.filter((p) => {
      const age = now - p._ts;
      return age > currentWindowMs && age <= currentWindowMs + previousWindowMs;
    });

    const currentCount = current.length;
    const previousCount = previous.length;
    const currentAuthors = [...new Set(current.map((p) => p.author).filter(Boolean))];
    const currentSubs = [...new Set(current.map((p) => p.subreddit).filter(Boolean))];
    const currentTimes = current.map((p) => p._ts).sort((a, b) => a - b);

    const spanMinutes = currentTimes.length >= 2
      ? minutesBetween(currentTimes[0], currentTimes[currentTimes.length - 1])
      : 0;

    const growth = scoreGrowth(currentCount, previousCount);
    const authors = scoreAuthors(currentAuthors.length);
    const subreddits = scoreSubreddits(currentSubs.length);
    const compression = scoreCompression(spanMinutes, currentCount);
    const baseline = scoreBaselineDelta(cluster.baseline?.steering_delta || 0);

    const score = round2(
      growth * 0.35 +
      subreddits * 0.2 +
      authors * 0.15 +
      compression * 0.2 +
      baseline * 0.1
    );

    const reason_codes = [];
    if (growth >= 0.5) reason_codes.push('growth_spike');
    if (subreddits >= 0.5) reason_codes.push('cross_subreddit_spread');
    if (authors >= 0.5) reason_codes.push('author_expansion');
    if (compression >= 0.5) reason_codes.push('compressed_window');
    if (baseline >= 0.5) reason_codes.push('baseline_delta');

    return {
      id: `outbreak-${idx + 1}`,
      cluster_id: cluster.id,
      narrative_id: cluster.narrative_id,
      label: cluster.label,
      state: stateFromScore(score),
      score,
      reason_codes,
      metrics: {
        current_count: currentCount,
        previous_count: previousCount,
        current_authors: currentAuthors.length,
        current_subreddits: currentSubs.length,
        span_minutes: spanMinutes,
        steering_delta: round2(cluster.baseline?.steering_delta || 0)
      }
    };
  });

  const rank = { severe: 4, outbreak: 3, watch: 2, observe: 1 };
  return outbreaks.sort((a, b) => rank[b.state] - rank[a.state] || b.score - a.score);
}

export function getOutbreakById(id, posts = [], analyses = []) {
  return buildOutbreaks(posts, analyses).find((x) => x.id === id) || null;
}
