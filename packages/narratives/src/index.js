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

function topKeywords(post, max = 6) {
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

function overlap(a, b) {
  const A = new Set(a);
  const B = new Set(b);
  let count = 0;
  for (const x of A) if (B.has(x)) count += 1;
  return count;
}

export function detectNarratives(posts = []) {
  const enriched = posts.map((post) => ({
    id: post.id,
    subreddit: post.subreddit,
    author: post.author,
    keywords: topKeywords(post)
  }));

  const groups = [];
  const used = new Set();

  for (let i = 0; i < enriched.length; i += 1) {
    if (used.has(enriched[i].id)) continue;

    const seed = enriched[i];
    const members = [seed];
    used.add(seed.id);

    for (let j = i + 1; j < enriched.length; j += 1) {
      if (used.has(enriched[j].id)) continue;
      if (overlap(seed.keywords, enriched[j].keywords) >= 2) {
        members.push(enriched[j]);
        used.add(enriched[j].id);
      }
    }

    if (members.length >= 1) {
      const keywordCounts = new Map();
      for (const m of members) {
        for (const k of m.keywords) {
          keywordCounts.set(k, (keywordCounts.get(k) || 0) + 1);
        }
      }

      const top = [...keywordCounts.entries()]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .slice(0, 5)
        .map(([k]) => k);

      groups.push({
        id: `nar-${(top.join('-') || seed.id).slice(0, 40)}`,
        label: top.join(' / ') || seed.id,
        keywords: top,
        post_ids: members.map((m) => m.id).sort(),
        authors: Array.from(new Set(members.map((m) => m.author))).sort(),
        subreddits: Array.from(new Set(members.map((m) => m.subreddit))).sort(),
        count: members.length
      });
    }
  }

  return groups.sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}
