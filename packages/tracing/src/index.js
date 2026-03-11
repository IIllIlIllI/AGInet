import { buildSpread } from '../../spread/src/index.js';

function toMs(v) {
  const n = new Date(v).getTime();
  return Number.isFinite(n) ? n : 0;
}

export function buildTraces(posts = []) {
  const spread = buildSpread(posts);
  const postMap = new Map(posts.map((p) => [p.id, p]));

  return spread.map((item, idx) => {
    const members = (item.post_ids || [])
      .map((id) => postMap.get(id))
      .filter(Boolean)
      .map((p) => ({ ...p, _ts: toMs(p.created_at) }))
      .filter((p) => p._ts > 0)
      .sort((a, b) => a._ts - b._ts);

    const bySubreddit = new Map();
    const earlyAuthors = [];
    const seenAuthors = new Set();

    for (const post of members) {
      if (!bySubreddit.has(post.subreddit)) {
        bySubreddit.set(post.subreddit, {
          subreddit: post.subreddit,
          first_seen: post.created_at,
          post_count: 0,
          authors: new Set()
        });
      }

      const row = bySubreddit.get(post.subreddit);
      row.post_count += 1;
      row.authors.add(post.author);

      if (earlyAuthors.length < 5 && post.author && !seenAuthors.has(post.author)) {
        earlyAuthors.push(post.author);
        seenAuthors.add(post.author);
      }
    }

    const spread_path = [...bySubreddit.values()]
      .map((x) => ({
        subreddit: x.subreddit,
        first_seen: x.first_seen,
        post_count: x.post_count,
        author_count: x.authors.size
      }))
      .sort((a, b) => toMs(a.first_seen) - toMs(b.first_seen));

    const seed_subreddits = spread_path.slice(0, 1).map((x) => x.subreddit);
    const amplifier_subreddits = spread_path
      .slice(1)
      .filter((x) => x.post_count >= 1)
      .map((x) => x.subreddit);

    return {
      id: `trace-${idx + 1}`,
      narrative_id: item.id,
      label: item.label,
      seed_subreddits,
      amplifier_subreddits,
      early_authors: earlyAuthors,
      spread_path,
      metrics: {
        total_posts: item.post_ids.length,
        total_subreddits: item.subreddit_count || 0,
        total_authors: item.author_count || 0,
        span_minutes: item.span_minutes || 0
      }
    };
  }).sort((a, b) => {
    return (b.metrics.total_subreddits - a.metrics.total_subreddits)
      || (b.metrics.total_posts - a.metrics.total_posts)
      || a.label.localeCompare(b.label);
  });
}

export function getTraceById(id, posts = []) {
  return buildTraces(posts).find((x) => x.id === id) || null;
}
