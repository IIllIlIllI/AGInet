#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve(process.env.HOME || ".", "projects", "truth-lens");

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function exists(p) {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

function backup(file) {
  if (!exists(file)) return;
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const bak = `${file}.bak.${stamp}`;
  fs.copyFileSync(file, bak);
  console.log(`[backup] ${bak}`);
}

function write(file, content) {
  ensureDir(path.dirname(file));
  backup(file);
  fs.writeFileSync(file, content, "utf8");
  console.log(`[write] ${path.relative(ROOT, file)}`);
}

const files = {
  storage: path.join(ROOT, "packages/storage/src/storage.js"),
  narratives: path.join(ROOT, "packages/narratives/src/index.js"),
  cluster: path.join(ROOT, "packages/cluster/src/index.js"),
  baseline: path.join(ROOT, "packages/baseline/src/index.js"),
  spread: path.join(ROOT, "packages/spread/src/index.js"),
  findings: path.join(ROOT, "packages/findings/src/index.js"),
  dashboard: path.join(ROOT, "packages/dashboard/src/index.js"),
  server: path.join(ROOT, "apps/api/src/server.ts"),
};

const STORAGE = `import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.env.HOME || '.', 'projects', 'truth-lens');
const DATA_DIR = path.join(ROOT, 'data');
const POSTS_DIR = path.join(DATA_DIR, 'posts');
const ANALYSIS_DIR = path.join(DATA_DIR, 'analysis');
const STATE_DIR = path.join(DATA_DIR, 'state');
const INGEST_STATE_FILE = path.join(STATE_DIR, 'ingest-state.json');

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function writeJson(file, value) {
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
}

function safeReadJson(file, fallback) {
  if (!fs.existsSync(file)) return fallback;
  try {
    return readJson(file);
  } catch {
    return fallback;
  }
}

export function savePost(post) {
  ensureDir(POSTS_DIR);
  const file = path.join(POSTS_DIR, \`\${post.id}.json\`);
  const now = new Date().toISOString();

  if (fs.existsSync(file)) {
    const existing = readJson(file);
    const merged = {
      ...existing,
      ...post,
      first_seen_at: existing.first_seen_at || now,
      last_seen_at: now,
      seen_count: Number(existing.seen_count || 1) + 1,
      updated_at: now
    };
    writeJson(file, merged);
    return { status: 'updated', post: merged };
  }

  const fresh = {
    ...post,
    first_seen_at: now,
    last_seen_at: now,
    seen_count: 1,
    updated_at: now
  };
  writeJson(file, fresh);
  return { status: 'created', post: fresh };
}

export function getPost(id) {
  const file = path.join(POSTS_DIR, \`\${id}.json\`);
  if (!fs.existsSync(file)) return null;
  return readJson(file);
}

export function listPosts() {
  ensureDir(POSTS_DIR);
  return fs.readdirSync(POSTS_DIR)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => readJson(path.join(POSTS_DIR, f)));
}

export function saveAnalysis(result) {
  ensureDir(ANALYSIS_DIR);
  const file = path.join(ANALYSIS_DIR, \`\${result.id}.json\`);
  const now = new Date().toISOString();

  if (fs.existsSync(file)) {
    const existing = readJson(file);
    const merged = {
      ...existing,
      ...result,
      analyzed_at: now,
      analysis_count: Number(existing.analysis_count || 1) + 1
    };
    writeJson(file, merged);
    return merged;
  }

  const fresh = {
    ...result,
    analyzed_at: now,
    analysis_count: 1
  };
  writeJson(file, fresh);
  return fresh;
}

export function getAnalysis(id) {
  const file = path.join(ANALYSIS_DIR, \`\${id}.json\`);
  if (!fs.existsSync(file)) return null;
  return readJson(file);
}

export function listAnalysis() {
  ensureDir(ANALYSIS_DIR);
  return fs.readdirSync(ANALYSIS_DIR)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => readJson(path.join(ANALYSIS_DIR, f)));
}

export function getIngestState() {
  ensureDir(STATE_DIR);
  return safeReadJson(INGEST_STATE_FILE, {
    last_run_at: null,
    subreddits: {}
  });
}

export function updateIngestState(subreddit, info = {}) {
  ensureDir(STATE_DIR);
  const state = getIngestState();
  const now = new Date().toISOString();

  state.last_run_at = now;
  state.subreddits[subreddit] = {
    ...(state.subreddits[subreddit] || {}),
    ...info,
    updated_at: now
  };

  writeJson(INGEST_STATE_FILE, state);
  return state;
}

export function listRecentPosts(limit = 10) {
  return listPosts()
    .sort((a, b) => {
      const ax = new Date(a.last_seen_at || a.updated_at || a.created_at || 0).getTime();
      const bx = new Date(b.last_seen_at || b.updated_at || b.created_at || 0).getTime();
      return bx - ax;
    })
    .slice(0, limit);
}

export function listNewPostsSinceLastRun(limit = 10) {
  const state = getIngestState();
  const lastRun = state?.last_run_at ? new Date(state.last_run_at).getTime() : 0;

  return listPosts()
    .filter((p) => {
      const firstSeen = new Date(p.first_seen_at || 0).getTime();
      return firstSeen >= lastRun;
    })
    .sort((a, b) => {
      const ax = new Date(a.first_seen_at || 0).getTime();
      const bx = new Date(b.first_seen_at || 0).getTime();
      return bx - ax;
    })
    .slice(0, limit);
}
`;

const NARRATIVES = `function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9\\s]/g, ' ')
    .split(/\\s+/)
    .filter(Boolean);
}

const STOP = new Set([
  'the','and','but','or','if','then','because','that','which','to','of','in','a','an',
  'is','are','it','this','we','they','you','for','with','was','were','be','as','on','at'
]);

function topKeywords(post, max = 6) {
  const counts = new Map();
  const tokens = tokenize(\`\${post.title || ''} \${post.body || ''}\`);
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

    const keywordCounts = new Map();
    for (const m of members) {
      for (const k of m.keywords) keywordCounts.set(k, (keywordCounts.get(k) || 0) + 1);
    }

    const top = [...keywordCounts.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 5)
      .map(([k]) => k);

    groups.push({
      id: \`nar-\${(top.join('-') || seed.id).slice(0, 40)}\`,
      label: top.join(' / ') || seed.id,
      keywords: top,
      post_ids: members.map((m) => m.id).sort(),
      authors: Array.from(new Set(members.map((m) => m.author))).sort(),
      subreddits: Array.from(new Set(members.map((m) => m.subreddit))).sort(),
      count: members.length
    });
  }

  return groups.sort((a, b) => b.count - a.count || a.label.localeCompare(b.label));
}
`;

const CLUSTER = `import { detectNarratives } from '../../narratives/src/index.js';

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
      id: \`clu-\${index + 1}\`,
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
`;

const BASELINE = `function avg(values) {
  if (!values.length) return 0;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function round3(n) {
  return Math.round(n * 1000) / 1000;
}

function tokenize(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9\\s]/g, ' ')
    .split(/\\s+/)
    .filter(Boolean);
}

const STOP = new Set([
  'the','and','but','or','if','then','because','that','which','to','of','in','a','an',
  'is','are','it','this','we','they','you','for','with','was','were','be','as','on','at'
]);

function topKeywords(post, max = 8) {
  const counts = new Map();
  const tokens = tokenize(\`\${post.title || ''} \${post.body || ''}\`);
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
      common_keywords: [...keywordCounts.entries()]
        .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
        .slice(0, 12)
        .map(([keyword, count]) => ({ keyword, count }))
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
    return { baseline_context: 'no baseline available', steering_delta: 0, coordination_delta: 0, synthetic_delta: 0 };
  }

  const avgSynthetic = avg(matches.map((m) => m.average_synthetic_language_likelihood || 0));
  const avgSteering = avg(matches.map((m) => m.average_narrative_steering_likelihood || 0));
  const avgCoordination = avg(matches.map((m) => m.average_coordination_likelihood || 0));

  return {
    baseline_context: \`compared against \${matches.length} subreddit baseline(s)\`,
    steering_delta: round3((cluster.average_narrative_steering_likelihood || 0) - avgSteering),
    coordination_delta: round3((cluster.average_coordination_likelihood || 0) - avgCoordination),
    synthetic_delta: round3((cluster.average_synthetic_language_likelihood || 0) - avgSynthetic)
  };
}
`;

const SPREAD = `import { detectNarratives } from '../../narratives/src/index.js';

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
`;

const FINDINGS = `function round2(n) {
  return Math.round(n * 100) / 100;
}

function band(n) {
  if (n < 0.2) return 'very low';
  if (n < 0.4) return 'low';
  if (n < 0.6) return 'moderate';
  if (n < 0.8) return 'high';
  return 'very high';
}

function pushIf(arr, cond, text) {
  if (cond) arr.push(text);
}

export function buildClusterFinding(cluster) {
  const findings = [];
  const cautions = [];

  pushIf(findings, cluster.size >= 2, \`This cluster contains \${cluster.size} related posts.\`);
  pushIf(findings, (cluster.subreddits || []).length >= 2, \`The framing appears across \${cluster.subreddits.length} subreddits.\`);
  pushIf(findings, (cluster.authors || []).length >= 2, \`The cluster involves \${cluster.authors.length} distinct authors.\`);
  pushIf(findings, (cluster.average_narrative_steering_likelihood || 0) >= 0.6, \`Narrative steering likelihood is \${band(cluster.average_narrative_steering_likelihood)}.\`);
  pushIf(findings, (cluster.average_coordination_likelihood || 0) >= 0.5, \`Coordination likelihood is \${band(cluster.average_coordination_likelihood)}.\`);
  pushIf(findings, (cluster.average_synthetic_language_likelihood || 0) >= 0.5, \`Synthetic-language likelihood is \${band(cluster.average_synthetic_language_likelihood)}.\`);

  if (cluster.baseline) {
    pushIf(findings, (cluster.baseline.steering_delta || 0) > 0.1, \`Steering is above subreddit baseline by \${round2(cluster.baseline.steering_delta)}.\`);
    pushIf(findings, (cluster.baseline.coordination_delta || 0) > 0.1, \`Coordination is above subreddit baseline by \${round2(cluster.baseline.coordination_delta)}.\`);
    pushIf(findings, (cluster.baseline.synthetic_delta || 0) > 0.1, \`Synthetic-language score is above subreddit baseline by \${round2(cluster.baseline.synthetic_delta)}.\`);
  }

  cautions.push('This does not prove falsehood or operator identity.');
  cautions.push('Repeated framing can also emerge organically during major events or memes.');

  return {
    id: cluster.id,
    entity_type: 'cluster',
    label: cluster.label,
    suspicion_rank: cluster.suspicion_rank,
    summary: buildClusterSummary(cluster),
    findings,
    cautions
  };
}

export function buildNarrativeFinding(spreadItem) {
  const findings = [];
  const cautions = [];

  pushIf(findings, spreadItem.post_ids.length >= 2, \`This narrative appears in \${spreadItem.post_ids.length} posts.\`);
  pushIf(findings, spreadItem.subreddit_count >= 2, \`It spread across \${spreadItem.subreddit_count} subreddits.\`);
  pushIf(findings, spreadItem.author_count >= 2, \`It was carried by \${spreadItem.author_count} distinct authors.\`);
  pushIf(findings, !!spreadItem.first_seen && !!spreadItem.last_seen, \`Observed window: \${spreadItem.first_seen} to \${spreadItem.last_seen}.\`);
  pushIf(findings, spreadItem.span_minutes > 0, \`Spread span is \${round2(spreadItem.span_minutes)} minutes.\`);
  pushIf(findings, spreadItem.time_compression_flag, 'This narrative appears in a compressed time window.');

  cautions.push('A compressed spread window is a clue, not proof of coordination.');
  cautions.push('Shared narratives can spread organically in fast-moving discussions.');

  return {
    id: spreadItem.id,
    entity_type: 'narrative',
    label: spreadItem.label,
    summary: buildNarrativeSummary(spreadItem),
    findings,
    cautions
  };
}

function buildClusterSummary(cluster) {
  const parts = [];
  if (cluster.label) parts.push(\`Shared framing: \${cluster.label}.\`);
  if (cluster.size >= 2) parts.push(\`\${cluster.size} related posts detected.\`);
  if ((cluster.subreddits || []).length >= 2) parts.push(\`Spread across \${cluster.subreddits.length} subreddits.\`);
  if ((cluster.average_narrative_steering_likelihood || 0) >= 0.6) parts.push('Steering signal is elevated.');
  if (cluster.baseline && (cluster.baseline.steering_delta || 0) > 0.1) parts.push('This exceeds local steering baseline.');
  return parts.join(' ');
}

function buildNarrativeSummary(item) {
  const parts = [];
  if (item.label) parts.push(\`Narrative: \${item.label}.\`);
  parts.push(\`Seen in \${item.post_ids.length} posts.\`);
  if (item.subreddit_count >= 2) parts.push(\`Spread across \${item.subreddit_count} subreddits.\`);
  if (item.time_compression_flag) parts.push('Appeared in a compressed time window.');
  return parts.join(' ');
}

export function buildAllFindings(clusters, spread) {
  return {
    cluster_findings: clusters.map(buildClusterFinding),
    narrative_findings: spread.map(buildNarrativeFinding)
  };
}
`;

const DASHBOARD = `function esc(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function card(title, body) {
  return \`<section class="card"><h2>\${esc(title)}</h2>\${body}</section>\`;
}

function list(items) {
  if (!items || !items.length) return '<p class="muted">No items yet.</p>';
  return \`<ul>\${items.map((x) => \`<li>\${x}</li>\`).join('')}</ul>\`;
}

function topProTip(clusterFindings, narrativeFindings) {
  const topCluster = (clusterFindings || [])[0];
  const topNarrative = (narrativeFindings || [])[0];

  if (topCluster) {
    return {
      headline: 'Top cluster signal',
      body: topCluster.summary || 'A suspicious cluster was detected.',
      caution: (topCluster.cautions || [])[0] || 'This is contextual guidance, not proof.'
    };
  }

  if (topNarrative) {
    return {
      headline: 'Top narrative signal',
      body: topNarrative.summary || 'A repeated narrative was detected.',
      caution: (topNarrative.cautions || [])[0] || 'This is contextual guidance, not proof.'
    };
  }

  return {
    headline: 'No major signal yet',
    body: 'The dashboard has not identified a strong cluster or narrative from the current local dataset.',
    caution: 'More data improves interpretation.'
  };
}

function timelineMini(item) {
  const bins = (item?.timeline || []).slice(0, 6);
  if (!bins.length) return '<div class="muted">No timeline yet.</div>';
  return \`<div class="timeline">\${bins.map((b) => \`<span class="bin"><strong>\${esc(b.count)}</strong><br><small>\${esc(b.bucket_start)}</small></span>\`).join('')}</div>\`;
}

function sortClusters(items, sort) {
  const arr = [...(items || [])];
  if (sort === 'size') {
    return arr.sort((a, b) => (b.cluster?.size || 0) - (a.cluster?.size || 0) || (b.cluster?.suspicion_rank || 0) - (a.cluster?.suspicion_rank || 0));
  }
  return arr.sort((a, b) => (b.cluster?.suspicion_rank || 0) - (a.cluster?.suspicion_rank || 0) || (b.cluster?.size || 0) - (a.cluster?.size || 0));
}

function filterBySubreddit(items, subreddit) {
  if (!subreddit) return items || [];
  return (items || []).filter((x) => (x.cluster?.subreddits || x.spread?.subreddits || []).includes(subreddit));
}

export function renderDashboard(data, opts = {}) {
  const summary = data.summary || {};
  const sort = opts.sort || 'rank';
  const subreddit = opts.subreddit || '';
  const q = opts.q || '';
  const rawClusterFindings = data.cluster_findings || [];
  const rawNarrativeFindings = data.narrative_findings || [];
  const spread = data.spread || [];
  const recentPosts = data.recent_posts || [];
  const newSinceLastRun = data.new_since_last_run || [];
  const ingestState = data.ingest_state || {};

  const spreadMap = new Map((spread || []).map((x) => [x.id, x]));
  const clusterMap = new Map((data.clusters || []).map((x) => [x.id, x]));

  const clusterFindings = sortClusters(
    filterBySubreddit(rawClusterFindings.map((f) => ({ ...f, cluster: clusterMap.get(f.id) })), subreddit),
    sort
  ).slice(0, 8);

  const narrativeFindings = filterBySubreddit(
    rawNarrativeFindings.map((f) => ({ ...f, spread: spreadMap.get(f.id) })),
    subreddit
  ).slice(0, 8);

  const baselines = subreddit
    ? (data.baselines || []).filter((b) => b.subreddit === subreddit)
    : (data.baselines || []).slice(0, 8);

  const tip = topProTip(clusterFindings, narrativeFindings);

  const summaryHtml = \`
    <div class="grid cols-4">
      <div class="metric"><div class="label">Posts</div><div class="value">\${esc(summary.total_posts ?? 0)}</div></div>
      <div class="metric"><div class="label">Avg Synthetic</div><div class="value">\${esc(summary.average_synthetic_language_likelihood ?? 0)}</div></div>
      <div class="metric"><div class="label">Avg Steering</div><div class="value">\${esc(summary.average_narrative_steering_likelihood ?? 0)}</div></div>
      <div class="metric"><div class="label">Avg Coordination</div><div class="value">\${esc(summary.average_coordination_likelihood ?? 0)}</div></div>
    </div>\`;

  const activityHtml = \`
    <p><strong>Last run:</strong> \${esc(ingestState.last_run_at || 'never')}</p>
    \${list(Object.entries(ingestState.subreddits || {}).map(([sub, info]) =>
      \`<strong>r/\${esc(sub)}</strong><br><span>fetched=\${esc(info.fetched_count ?? 0)} created=\${esc(info.created_count ?? 0)} updated=\${esc(info.updated_count ?? 0)}</span>\`
    ))}
  \`;

  const newPostsHtml = list(newSinceLastRun.map((p) =>
    \`<strong>\${esc(p.title || p.id)}</strong><br><span>r/\${esc(p.subreddit)} by \${esc(p.author)}</span><br><span class="muted">first_seen=\${esc(p.first_seen_at || '')}</span>\`
  ));

  const recentPostsHtml = list(recentPosts.map((p) =>
    \`<strong>\${esc(p.title || p.id)}</strong><br><span>r/\${esc(p.subreddit)} by \${esc(p.author)}</span><br><span class="muted">last_seen=\${esc(p.last_seen_at || p.updated_at || '')} seen_count=\${esc(p.seen_count ?? 0)}</span>\`
  ));

  const controlsHtml = \`
    <form method="GET" action="/dashboard" class="controls">
      <label>Sort
        <select name="sort">
          <option value="rank" \${sort === 'rank' ? 'selected' : ''}>Suspicion Rank</option>
          <option value="size" \${sort === 'size' ? 'selected' : ''}>Cluster Size</option>
        </select>
      </label>
      <label>Subreddit
        <input type="text" name="subreddit" value="\${esc(subreddit)}" placeholder="technology">
      </label>
      <label>Search
        <input type="text" name="q" value="\${esc(q)}" placeholder="trust">
      </label>
      <button type="submit">Apply</button>
      <a class="button-link" href="/dashboard">Reset</a>
    </form>\`;

  const proTipHtml = \`
    <div class="protip">
      <div class="protip-label">PRO TIP</div>
      <div class="protip-headline">\${esc(tip.headline)}</div>
      <div class="protip-body">\${esc(tip.body)}</div>
      <div class="muted">\${esc(tip.caution)}</div>
    </div>\`;

  const clustersHtml = list(clusterFindings.map((f) => {
    const findings = (f.findings || []).slice(0, 3).map((x) => esc(x)).join(' • ');
    const cluster = f.cluster || {};
    return \`<a href="/dashboard/cluster/\${esc(f.id)}"><strong>\${esc(f.label || f.id)}</strong></a><br><span>\${esc(f.summary || '')}</span><br><span class="muted">rank=\${esc(cluster.suspicion_rank ?? '')} size=\${esc(cluster.size ?? '')} \${findings}</span>\`;
  }));

  const narrativesHtml = list(narrativeFindings.map((f) => {
    const findings = (f.findings || []).slice(0, 3).map((x) => esc(x)).join(' • ');
    const s = f.spread || {};
    return \`<a href="/dashboard/narrative/\${esc(f.id)}"><strong>\${esc(f.label || f.id)}</strong></a><br><span>\${esc(f.summary || '')}</span>\${timelineMini(s)}<br><span class="muted">\${findings}</span>\`;
  }));

  const baselinesHtml = list(baselines.map((b) => {
    const kws = (b.common_keywords || []).slice(0, 5).map((k) => esc(k.keyword)).join(', ');
    return \`<strong><a href="/dashboard?subreddit=\${encodeURIComponent(b.subreddit)}">r/\${esc(b.subreddit)}</a></strong><br><span>posts=\${esc(b.post_count)} synthetic=\${esc(b.average_synthetic_language_likelihood)} steering=\${esc(b.average_narrative_steering_likelihood)} coordination=\${esc(b.average_coordination_likelihood)}</span><br><span class="muted">keywords: \${kws}</span>\`;
  }));

  const linksHtml = list([
    '<a href="/dashboard">/dashboard</a>',
    '<a href="/health">/health</a>',
    '<a href="/summary">/summary</a>',
    '<a href="/activity">/activity</a>',
    '<a href="/findings">/findings</a>',
    '<a href="/findings/clusters">/findings/clusters</a>',
    '<a href="/findings/narratives">/findings/narratives</a>',
    '<a href="/baselines">/baselines</a>',
    '<a href="/spread">/spread</a>',
    '<a href="/clusters">/clusters</a>',
    '<a href="/narratives">/narratives</a>'
  ]);

  const searchHtml = q
    ? card('Search Query', \`<p>Current search: <strong>\${esc(q)}</strong></p><p class="muted">Use the dashboard controls.</p>\`)
    : '';

  return \`<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Truth Lens Dashboard</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 0; padding: 16px; background: #0b1020; color: #e8ecf1; }
    h1 { margin-top: 0; font-size: 28px; }
    h2 { margin: 0 0 10px 0; font-size: 18px; }
    .muted { color: #9aa4b2; }
    .grid { display: grid; gap: 12px; }
    .cols-4 { grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); }
    .card { background: #121a2b; border: 1px solid #25314a; border-radius: 14px; padding: 14px; margin-bottom: 14px; }
    .metric { background: #0f1727; border: 1px solid #23304a; border-radius: 12px; padding: 12px; }
    .label { font-size: 12px; color: #9aa4b2; }
    .value { font-size: 24px; font-weight: 700; margin-top: 4px; }
    ul { margin: 0; padding-left: 18px; }
    li { margin-bottom: 10px; }
    a { color: #8ec5ff; text-decoration: none; }
    .controls { display: flex; gap: 10px; flex-wrap: wrap; align-items: end; }
    .controls label { display: flex; flex-direction: column; gap: 4px; font-size: 14px; }
    input, select, button, .button-link { background: #0f1727; color: #e8ecf1; border: 1px solid #23304a; border-radius: 10px; padding: 8px 10px; }
    button, .button-link { cursor: pointer; text-decoration: none; display: inline-block; }
    .protip { background: linear-gradient(180deg, #15213a, #0f1727); border: 1px solid #35538a; border-radius: 14px; padding: 14px; }
    .protip-label { font-size: 12px; color: #8ec5ff; font-weight: 700; letter-spacing: 0.08em; }
    .protip-headline { font-size: 20px; font-weight: 700; margin-top: 6px; }
    .protip-body { margin-top: 8px; margin-bottom: 8px; }
    .timeline { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 8px; margin-bottom: 8px; }
    .bin { background: #0f1727; border: 1px solid #23304a; border-radius: 8px; padding: 6px; min-width: 88px; }
  </style>
</head>
<body>
  \${card('PRO TIP', proTipHtml)}
  <h1>Truth Lens Dashboard</h1>
  <p class="muted">Local prototype dashboard for findings, baselines, narratives, and clusters.</p>
  \${card('Summary', summaryHtml)}
  \${card('Recent Activity', activityHtml)}
  \${card('New Since Last Run', newPostsHtml)}
  \${card('Recently Seen Posts', recentPostsHtml)}
  \${card('Controls', controlsHtml)}
  \${searchHtml}
  \${card('Top Cluster Findings', clustersHtml)}
  \${card('Top Narrative Findings', narrativesHtml)}
  \${card('Subreddit Baselines', baselinesHtml)}
  \${card('Routes', linksHtml)}
</body>
</html>\`;
}

export function renderClusterDetail(data) {
  const c = data.cluster || {};
  const f = data.finding || {};
  const baseline = c.baseline || {};
  const related = (data.relatedNarratives || []).map((x) => \`<li><a href="/dashboard/narrative/\${esc(x.id)}">\${esc(x.label || x.id)}</a></li>\`).join('') || '<li class="muted">No related narratives.</li>';

  return \`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Cluster Detail</title><style>body{font-family:system-ui,sans-serif;margin:0;padding:16px;background:#0b1020;color:#e8ecf1}.card{background:#121a2b;border:1px solid #25314a;border-radius:14px;padding:14px;margin-bottom:14px}a{color:#8ec5ff}.muted{color:#9aa4b2}ul{padding-left:18px}</style></head><body><p><a href="/dashboard">← Back to dashboard</a></p><div class="card"><h1>\${esc(f.label || c.label || c.id)}</h1><p>\${esc(f.summary || '')}</p><p class="muted">rank=\${esc(c.suspicion_rank)} size=\${esc(c.size)}</p></div><div class="card"><h2>Findings</h2><ul>\${(f.findings || []).map((x) => \`<li>\${esc(x)}</li>\`).join('')}</ul></div><div class="card"><h2>Baseline Context</h2><p>\${esc(baseline.baseline_context || 'No baseline context')}</p><ul><li>steering delta: \${esc(baseline.steering_delta ?? 0)}</li><li>coordination delta: \${esc(baseline.coordination_delta ?? 0)}</li><li>synthetic delta: \${esc(baseline.synthetic_delta ?? 0)}</li></ul></div><div class="card"><h2>Members</h2><p>subreddits: \${esc((c.subreddits || []).join(', '))}</p><p>authors: \${esc((c.authors || []).join(', '))}</p><p>post_ids: \${esc((c.post_ids || []).join(', '))}</p></div><div class="card"><h2>Related Narratives</h2><ul>\${related}</ul></div></body></html>\`;
}

export function renderNarrativeDetail(data) {
  const n = data.spread || {};
  const f = data.finding || {};
  const related = (data.relatedClusters || []).map((x) => \`<li><a href="/dashboard/cluster/\${esc(x.id)}">\${esc(x.label || x.id)}</a></li>\`).join('') || '<li class="muted">No related clusters.</li>';

  return \`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Narrative Detail</title><style>body{font-family:system-ui,sans-serif;margin:0;padding:16px;background:#0b1020;color:#e8ecf1}.card{background:#121a2b;border:1px solid #25314a;border-radius:14px;padding:14px;margin-bottom:14px}a{color:#8ec5ff}.muted{color:#9aa4b2}ul{padding-left:18px}.timeline{display:flex;gap:6px;flex-wrap:wrap}.bin{background:#0f1727;border:1px solid #23304a;border-radius:8px;padding:6px;min-width:88px}</style></head><body><p><a href="/dashboard">← Back to dashboard</a></p><div class="card"><h1>\${esc(f.label || n.label || n.id)}</h1><p>\${esc(f.summary || '')}</p><p class="muted">first_seen=\${esc(n.first_seen)} last_seen=\${esc(n.last_seen)} span_minutes=\${esc(n.span_minutes)}</p></div><div class="card"><h2>Findings</h2><ul>\${(f.findings || []).map((x) => \`<li>\${esc(x)}</li>\`).join('')}</ul></div><div class="card"><h2>Spread</h2><p>subreddits: \${esc((n.subreddits || []).join(', '))}</p><p>authors: \${esc((n.authors || []).join(', '))}</p><p>compressed window: \${esc(n.time_compression_flag)}</p></div><div class="card"><h2>Timeline</h2><div class="timeline">\${(n.timeline || []).map((b) => \`<span class="bin"><strong>\${esc(b.count)}</strong><br><small>\${esc(b.bucket_start)}</small></span>\`).join('')}</div></div><div class="card"><h2>Related Clusters</h2><ul>\${related}</ul></div></body></html>\`;
}
`;

const SERVER = `import http from 'node:http';
import {
  listPosts,
  getPost,
  listAnalysis,
  getAnalysis,
  getIngestState,
  listRecentPosts,
  listNewPostsSinceLastRun
} from '../../../packages/storage/src/storage.js';
import { detectNarratives } from '../../../packages/narratives/src/index.js';
import { detectClusters } from '../../../packages/cluster/src/index.js';
import { buildBaselines, getBaselineForSubreddit, compareClusterToBaselines } from '../../../packages/baseline/src/index.js';
import { buildSpread, getSpreadById, getTimelineById } from '../../../packages/spread/src/index.js';
import { buildClusterFinding, buildNarrativeFinding, buildAllFindings } from '../../../packages/findings/src/index.js';
import { renderDashboard, renderClusterDetail, renderNarrativeDetail } from '../../../packages/dashboard/src/index.js';

const PORT = Number(process.env.API_PORT ?? 3001);

function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data, null, 2));
}

function html(res, status, markup) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(markup);
}

function notFound(res) {
  return json(res, 404, { error: 'not_found' });
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

function summarize(analysisItems) {
  const total = analysisItems.length;
  const avgSynthetic = total ? analysisItems.reduce((a, x) => a + (x.score.synthetic_language_likelihood || 0), 0) / total : 0;
  const avgSteering = total ? analysisItems.reduce((a, x) => a + (x.score.narrative_steering_likelihood || 0), 0) / total : 0;
  const avgCoordination = total ? analysisItems.reduce((a, x) => a + (x.score.coordination_likelihood || 0), 0) / total : 0;

  const topFlagged = [...analysisItems]
    .sort((a, b) => (b.score.narrative_steering_likelihood + b.score.coordination_likelihood) - (a.score.narrative_steering_likelihood + a.score.coordination_likelihood))
    .slice(0, 5)
    .map((x) => ({
      id: x.id,
      subreddit: x.post.subreddit,
      author: x.post.author,
      score: x.score,
      reasons: x.score.reasons
    }));

  return {
    total_posts: total,
    average_synthetic_language_likelihood: round2(avgSynthetic),
    average_narrative_steering_likelihood: round2(avgSteering),
    average_coordination_likelihood: round2(avgCoordination),
    top_flagged: topFlagged
  };
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', 'http://localhost');
  const parts = url.pathname.split('/').filter(Boolean);

  if (url.pathname === '/health') {
    return json(res, 200, {
      status: 'ok',
      service: 'truth-lens-api',
      time_utc: new Date().toISOString(),
      version: 'v1'
    });
  }

  if (url.pathname === '/posts') return json(res, 200, listPosts());

  if (parts[0] === 'posts' && parts[1]) {
    const post = getPost(parts[1]);
    return post ? json(res, 200, post) : notFound(res);
  }

  if (url.pathname === '/analysis') return json(res, 200, listAnalysis());

  if (parts[0] === 'analysis' && parts[1]) {
    const analysis = getAnalysis(parts[1]);
    return analysis ? json(res, 200, analysis) : notFound(res);
  }

  if (url.pathname === '/summary') return json(res, 200, summarize(listAnalysis()));

  if (url.pathname === '/activity') {
    return json(res, 200, {
      ingest_state: getIngestState(),
      recent_posts: listRecentPosts(10),
      new_since_last_run: listNewPostsSinceLastRun(10)
    });
  }

  if (url.pathname === '/baselines') return json(res, 200, buildBaselines(listPosts(), listAnalysis()));

  if (parts[0] === 'baselines' && parts[1]) {
    const item = getBaselineForSubreddit(parts[1], listPosts(), listAnalysis());
    return item ? json(res, 200, item) : notFound(res);
  }

  if (url.pathname === '/narratives') return json(res, 200, detectNarratives(listPosts()));

  if (parts[0] === 'narratives' && parts[1]) {
    const item = detectNarratives(listPosts()).find((x) => x.id === parts[1]);
    return item ? json(res, 200, item) : notFound(res);
  }

  if (url.pathname === '/clusters') {
    const posts = listPosts();
    const analyses = listAnalysis();
    const baselines = buildBaselines(posts, analyses);
    const clusters = detectClusters(posts, analyses).map((cluster) => ({
      ...cluster,
      baseline: compareClusterToBaselines(cluster, baselines)
    }));
    return json(res, 200, clusters);
  }

  if (parts[0] === 'clusters' && parts[1]) {
    const posts = listPosts();
    const analyses = listAnalysis();
    const baselines = buildBaselines(posts, analyses);
    const item = detectClusters(posts, analyses)
      .map((cluster) => ({ ...cluster, baseline: compareClusterToBaselines(cluster, baselines) }))
      .find((x) => x.id === parts[1]);
    return item ? json(res, 200, item) : notFound(res);
  }

  if (url.pathname === '/spread') return json(res, 200, buildSpread(listPosts()));

  if (parts[0] === 'spread' && parts[1]) {
    const item = getSpreadById(parts[1], listPosts());
    return item ? json(res, 200, item) : notFound(res);
  }

  if (parts[0] === 'timeline' && parts[1]) {
    const item = getTimelineById(parts[1], listPosts());
    return item ? json(res, 200, item) : notFound(res);
  }

  if (url.pathname === '/findings') {
    const posts = listPosts();
    const analyses = listAnalysis();
    const baselines = buildBaselines(posts, analyses);
    const clusters = detectClusters(posts, analyses).map((cluster) => ({
      ...cluster,
      baseline: compareClusterToBaselines(cluster, baselines)
    }));
    const spread = buildSpread(posts);
    return json(res, 200, buildAllFindings(clusters, spread));
  }

  if (url.pathname === '/findings/clusters') {
    const posts = listPosts();
    const analyses = listAnalysis();
    const baselines = buildBaselines(posts, analyses);
    const clusters = detectClusters(posts, analyses).map((cluster) => ({
      ...cluster,
      baseline: compareClusterToBaselines(cluster, baselines)
    }));
    return json(res, 200, clusters.map(buildClusterFinding));
  }

  if (url.pathname === '/findings/narratives') {
    return json(res, 200, buildSpread(listPosts()).map(buildNarrativeFinding));
  }

  if (parts[0] === 'findings' && parts[1] === 'cluster' && parts[2]) {
    const posts = listPosts();
    const analyses = listAnalysis();
    const baselines = buildBaselines(posts, analyses);
    const item = detectClusters(posts, analyses)
      .map((cluster) => ({ ...cluster, baseline: compareClusterToBaselines(cluster, baselines) }))
      .find((x) => x.id === parts[2]);
    return item ? json(res, 200, buildClusterFinding(item)) : notFound(res);
  }

  if (parts[0] === 'findings' && parts[1] === 'narrative' && parts[2]) {
    const item = getSpreadById(parts[2], listPosts());
    return item ? json(res, 200, buildNarrativeFinding(item)) : notFound(res);
  }

  if (url.pathname === '/dashboard') {
    const posts = listPosts();
    const analyses = listAnalysis();
    const baselines = buildBaselines(posts, analyses);
    const clusters = detectClusters(posts, analyses).map((cluster) => ({
      ...cluster,
      baseline: compareClusterToBaselines(cluster, baselines)
    }));
    const spread = buildSpread(posts);
    const findings = buildAllFindings(clusters, spread);
    const summaryData = summarize(analyses);
    return html(res, 200, renderDashboard({
      summary: summaryData,
      baselines,
      clusters,
      spread,
      cluster_findings: findings.cluster_findings,
      narrative_findings: findings.narrative_findings,
      recent_posts: listRecentPosts(10),
      new_since_last_run: listNewPostsSinceLastRun(10),
      ingest_state: getIngestState()
    }, {
      sort: url.searchParams.get('sort') || 'rank',
      subreddit: url.searchParams.get('subreddit') || '',
      q: url.searchParams.get('q') || ''
    }));
  }

  if (parts[0] === 'dashboard' && parts[1] === 'cluster' && parts[2]) {
    const posts = listPosts();
    const analyses = listAnalysis();
    const baselines = buildBaselines(posts, analyses);
    const cluster = detectClusters(posts, analyses)
      .map((x) => ({ ...x, baseline: compareClusterToBaselines(x, baselines) }))
      .find((x) => x.id === parts[2]);
    if (!cluster) return notFound(res);
    const finding = buildClusterFinding(cluster);
    const relatedNarratives = detectNarratives(posts).filter((n) => n.id === cluster.narrative_id);
    return html(res, 200, renderClusterDetail({ cluster, finding, relatedNarratives }));
  }

  if (parts[0] === 'dashboard' && parts[1] === 'narrative' && parts[2]) {
    const spread = getSpreadById(parts[2], listPosts());
    if (!spread) return notFound(res);
    const finding = buildNarrativeFinding(spread);
    const relatedClusters = detectClusters(listPosts(), listAnalysis()).filter((c) => c.narrative_id === spread.id);
    return html(res, 200, renderNarrativeDetail({ spread, finding, relatedClusters }));
  }

  return json(res, 200, {
    message: 'truth-lens api',
    routes: [
      '/health',
      '/posts',
      '/posts/:id',
      '/analysis',
      '/analysis/:id',
      '/summary',
      '/activity',
      '/baselines',
      '/baselines/:subreddit',
      '/narratives',
      '/narratives/:id',
      '/clusters',
      '/clusters/:id',
      '/spread',
      '/spread/:id',
      '/timeline/:id',
      '/findings',
      '/findings/clusters',
      '/findings/cluster/:id',
      '/findings/narratives',
      '/findings/narrative/:id',
      '/dashboard',
      '/dashboard/cluster/:id',
      '/dashboard/narrative/:id'
    ]
  });
});

server.listen(PORT, () => {
  console.log(\`Truth Lens API running on port \${PORT}\`);
});
`;

function fixStorage() {
  write(files.storage, STORAGE);
}

function fixPackages() {
  write(files.narratives, NARRATIVES);
  write(files.cluster, CLUSTER);
  write(files.baseline, BASELINE);
  write(files.spread, SPREAD);
  write(files.findings, FINDINGS);
}

function fixDashboard() {
  write(files.dashboard, DASHBOARD);
}

function fixApi() {
  write(files.server, SERVER);
}

function fixCritical() {
  fixStorage();
  fixPackages();
  fixDashboard();
  fixApi();
  console.log("[done] critical files restored");
}

function help() {
  console.log(`
Usage:
  node tools/read-agent/fix-repo.mjs critical
  node tools/read-agent/fix-repo.mjs storage
  node tools/read-agent/fix-repo.mjs packages
  node tools/read-agent/fix-repo.mjs dashboard
  node tools/read-agent/fix-repo.mjs api
`);
}

const cmd = process.argv[2];

switch (cmd) {
  case "critical":
    fixCritical();
    break;
  case "storage":
    fixStorage();
    break;
  case "packages":
    fixPackages();
    break;
  case "dashboard":
    fixDashboard();
    break;
  case "api":
    fixApi();
    break;
  default:
    help();
}
