import { buildAlerts } from '../../news/src/index.js';
import { buildOutbreaks } from '../../outbreak/src/index.js';
import { buildSignatures } from '../../signatures/src/index.js';
import { buildTraces } from '../../tracing/src/index.js';

function round2(n) {
  return Math.round(n * 100) / 100;
}

function clamp(n, min = 0, max = 1) {
  return Math.max(min, Math.min(max, n));
}

function confidenceBand(score) {
  if (score >= 0.75) return 'high';
  if (score >= 0.45) return 'medium';
  return 'low';
}

function scoreFromAlert(alert) {
  return clamp(alert?.score || 0);
}

function scoreFromOutbreak(outbreak) {
  return clamp(outbreak?.score || 0);
}

function scoreFromSignature(signature) {
  if (!signature) return 0;
  const postScore = clamp((signature.post_count || 0) / 8);
  const authorScore = clamp((signature.author_count || 0) / 5);
  const subredditScore = clamp((signature.subreddit_count || 0) / 4);
  return round2(postScore * 0.5 + authorScore * 0.3 + subredditScore * 0.2);
}

function scoreFromTrace(trace) {
  if (!trace) return 0;
  const subs = clamp((trace.metrics?.total_subreddits || 0) / 4);
  const posts = clamp((trace.metrics?.total_posts || 0) / 8);
  const span = trace.metrics?.span_minutes || 0;
  const compression =
    span <= 15 ? 1 :
    span <= 30 ? 0.8 :
    span <= 60 ? 0.5 :
    span <= 120 ? 0.25 : 0.1;
  return round2(subs * 0.4 + posts * 0.35 + compression * 0.25);
}

export function buildFingerprints(posts = [], analyses = []) {
  const alerts = buildAlerts(posts, analyses);
  const outbreaks = buildOutbreaks(posts, analyses);
  const signatures = buildSignatures(posts, analyses);
  const traces = buildTraces(posts);

  const alertByNarrative = new Map(alerts.map((a) => [a.narrative_id, a]));
  const outbreakByNarrative = new Map(outbreaks.map((o) => [o.narrative_id, o]));
  const traceByNarrative = new Map(traces.map((t) => [t.narrative_id, t]));

  const fingerprints = signatures.map((sig, idx) => {
    const narrativeMatches = [];

    for (const narrativeId of [...alertByNarrative.keys()]) {
      const alert = alertByNarrative.get(narrativeId);
      const outbreak = outbreakByNarrative.get(narrativeId);
      const trace = traceByNarrative.get(narrativeId);

      const sigTerms = new Set((sig.top_terms || []).map(String));
      const alertTerms = new Set(String(alert?.label || '').toLowerCase().split(/[^a-z0-9]+/).filter(Boolean));

      let overlap = 0;
      for (const t of sigTerms) {
        if (alertTerms.has(t)) overlap += 1;
      }

      if (
        overlap >= 1 ||
        (trace?.seed_subreddits || []).some((s) => (sig.subreddits || []).includes(s)) ||
        (trace?.amplifier_subreddits || []).some((s) => (sig.subreddits || []).includes(s))
      ) {
        narrativeMatches.push(narrativeId);
      }
    }

    const linkedAlerts = narrativeMatches.map((id) => alertByNarrative.get(id)).filter(Boolean);
    const linkedOutbreaks = narrativeMatches.map((id) => outbreakByNarrative.get(id)).filter(Boolean);
    const linkedTraces = narrativeMatches.map((id) => traceByNarrative.get(id)).filter(Boolean);

    const maxAlert = linkedAlerts.reduce((m, x) => Math.max(m, scoreFromAlert(x)), 0);
    const maxOutbreak = linkedOutbreaks.reduce((m, x) => Math.max(m, scoreFromOutbreak(x)), 0);
    const maxTrace = linkedTraces.reduce((m, x) => Math.max(m, scoreFromTrace(x)), 0);
    const sigScore = scoreFromSignature(sig);

    const score = round2(
      sigScore * 0.35 +
      maxAlert * 0.2 +
      maxOutbreak * 0.25 +
      maxTrace * 0.2
    );

    return {
      id: `fp-${idx + 1}`,
      label: sig.label,
      confidence: confidenceBand(score),
      score,
      linked_narratives: narrativeMatches,
      signature_id: sig.id,
      post_ids: sig.post_ids,
      authors: sig.authors,
      subreddits: sig.subreddits,
      top_terms: sig.top_terms,
      components: {
        signature_score: sigScore,
        alert_score: maxAlert,
        outbreak_score: maxOutbreak,
        trace_score: maxTrace
      },
      signature: sig.signature
    };
  });

  const rank = { high: 3, medium: 2, low: 1 };
  return fingerprints.sort((a, b) => rank[b.confidence] - rank[a.confidence] || b.score - a.score);
}

export function getFingerprintById(id, posts = [], analyses = []) {
  return buildFingerprints(posts, analyses).find((x) => x.id === id) || null;
}
