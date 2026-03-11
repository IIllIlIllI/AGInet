import { detectNarratives } from '../../narratives/src/index.js';

function toMs(value) {
  const n = new Date(value).getTime();
  return Number.isFinite(n) ? n : 0;
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

function minutesBetween(a, b) {
  return round2(Math.max(0, (toMs(b) - toMs(a)) / 60000));
}

function bucketHour(iso) {
  const d = new Date(iso);
  if (!Number.isFinite(d.getTime())) return 'unknown';
  d.setMinutes(0, 0, 0);
  return d.toISOString();
}

export function buildSpread(posts = []) {
  const narratives = detectNarratives(posts);
  const postMap = new Map(posts.map((p) => [p.id, p]));

  return narratives.map((nar) => {
    const members = nar.post_ids.map((id) => postMap.get(id)).filter(Boolean);
    const times = members.map((m) => m.created_at).filter(Boolean).sort();
    const first_seen = times[0] || null;
    const last_seen = times[times.length - 1] || null;
    const span_minutes = first_seen && last_seen ? minutesBetween(first_seen, last_seen) : 0;
    const subreddits = Array.from(new Set(members.map((m) => m.subreddit).filter(Boolean))).sort();
    const authors = Array.from(new Set(members.map((m) => m.author).filter(Boolean))).sort();
    const hourly = new Map();

    for (const m of members) {
      const bucket = bucketHour(m.created_at);
      hourly.set(bucket, (hourly.get(bucket) || 0) + 1);
    }

    const timeline = [...hourly.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([bucket_start, count]) => ({ bucket_start, count }));

    return {
      id: nar.id,
      label: nar.label,
      keywords: nar.keywords,
      post_ids: nar.post_ids,
      authors,
      subreddits,
      author_count: authors.length,
      subreddit_count: subreddits.length,
      first_seen,
      last_seen,
      span_minutes,
      time_compression_flag: nar.count >= 2 && span_minutes <= 120,
      timeline
    };
  }).sort((a, b) => {
    if (a.time_compression_flag !== b.time_compression_flag) return a.time_compression_flag ? -1 : 1;
    return b.post_ids.length - a.post_ids.length || a.label.localeCompare(b.label);
  });
}

export function getSpreadById(id, posts = []) {
  return buildSpread(posts).find((x) => x.id === id) || null;
}

export function getTimelineById(id, posts = []) {
  const item = getSpreadById(id, posts);
  if (!item) return null;
  return {
    id: item.id,
    label: item.label,
    first_seen: item.first_seen,
    last_seen: item.last_seen,
    span_minutes: item.span_minutes,
    timeline: item.timeline
  };
}
