import http from 'node:http';
import { listPosts, getPost, listAnalysis, getAnalysis } from '../../../packages/storage/src/storage.js';

const PORT = Number(process.env.API_PORT ?? 3001);

function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data, null, 2));
}

function notFound(res) {
  return json(res, 404, { error: 'not_found' });
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

function round2(n) {
  return Math.round(n * 100) / 100;
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

  if (url.pathname === '/posts') {
    return json(res, 200, listPosts());
  }

  if (parts[0] === 'posts' && parts[1]) {
    const post = getPost(parts[1]);
    return post ? json(res, 200, post) : notFound(res);
  }

  if (url.pathname === '/analysis') {
    return json(res, 200, listAnalysis());
  }

  if (parts[0] === 'analysis' && parts[1]) {
    const analysis = getAnalysis(parts[1]);
    return analysis ? json(res, 200, analysis) : notFound(res);
  }

  if (url.pathname === '/summary') {
    return json(res, 200, summarize(listAnalysis()));
  }

  return json(res, 200, {
    message: 'truth-lens api',
    routes: ['/health', '/posts', '/posts/:id', '/analysis', '/analysis/:id', '/summary']
  });
});

server.listen(PORT, () => {
  console.log(`Truth Lens API running on port ${PORT}`);
});
