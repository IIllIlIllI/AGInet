import { buildPrismProfile, scorePrism } from '../../../packages/prism/src/index.js';
import { buildAlerts, getAlertById } from '../../../packages/news/src/index.js';
import http from 'node:http';
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
import { buildFullGraph, renderFullGraphPage } from '../../../packages/graphfull/src/index.js';
import { buildOutbreaks, getOutbreakById } from '../../../packages/outbreak/src/index.js';

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

if (url.pathname === '/alerts') {    return json(res, 200, buildAlerts(listPosts(), listAnalysis()));  }  if (parts[0] === 'alerts' && parts[1]) {    const item = getAlertById(parts[1], listPosts(), listAnalysis());    return item ? json(res, 200, item) : notFound(res);  }
  if (url.pathname === '/graph/full') {
    return json(res, 200, buildFullGraph(listPosts(), listAnalysis()));
  }

  if (url.pathname === '/dashboard/graph-full') {
    return html(res, 200, renderFullGraphPage(buildFullGraph(listPosts(), listAnalysis())));
  }

    return json(res, 200, buildFingerprints(listPosts(), listAnalysis()));
  }

  if (parts[0] === 'fingerprints' && parts[1]) {
    const item = getFingerprintById(parts[1], listPosts(), listAnalysis());
    return item ? json(res, 200, item) : notFound(res);
  }

    return json(res, 200, buildTraces(listPosts()));
  }

  if (parts[0] === 'traces' && parts[1]) {
    const item = getTraceById(parts[1], listPosts());
    return item ? json(res, 200, item) : notFound(res);
  }

  if (url.pathname === '/outbreaks') {
    return json(res, 200, buildOutbreaks(listPosts(), listAnalysis()));
  }

  if (parts[0] === 'outbreaks' && parts[1]) {
    const item = getOutbreakById(parts[1], listPosts(), listAnalysis());
    return item ? json(res, 200, item) : notFound(res);
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
  console.log(`Truth Lens API running on port ${PORT}`);
});
