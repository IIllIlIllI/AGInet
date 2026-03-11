function round2(n) {
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

  pushIf(findings, cluster.size >= 2, `This cluster contains ${cluster.size} related posts.`);
  pushIf(findings, (cluster.subreddits || []).length >= 2, `The framing appears across ${cluster.subreddits.length} subreddits.`);
  pushIf(findings, (cluster.authors || []).length >= 2, `The cluster involves ${cluster.authors.length} distinct authors.`);
  pushIf(findings, (cluster.average_narrative_steering_likelihood || 0) >= 0.6, `Narrative steering likelihood is ${band(cluster.average_narrative_steering_likelihood)}.`);
  pushIf(findings, (cluster.average_coordination_likelihood || 0) >= 0.5, `Coordination likelihood is ${band(cluster.average_coordination_likelihood)}.`);
  pushIf(findings, (cluster.average_synthetic_language_likelihood || 0) >= 0.5, `Synthetic-language likelihood is ${band(cluster.average_synthetic_language_likelihood)}.`);

  if (cluster.baseline) {
    pushIf(findings, (cluster.baseline.steering_delta || 0) > 0.1, `Steering is above subreddit baseline by ${round2(cluster.baseline.steering_delta)}.`);
    pushIf(findings, (cluster.baseline.coordination_delta || 0) > 0.1, `Coordination is above subreddit baseline by ${round2(cluster.baseline.coordination_delta)}.`);
    pushIf(findings, (cluster.baseline.synthetic_delta || 0) > 0.1, `Synthetic-language score is above subreddit baseline by ${round2(cluster.baseline.synthetic_delta)}.`);
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

  pushIf(findings, spreadItem.post_ids.length >= 2, `This narrative appears in ${spreadItem.post_ids.length} posts.`);
  pushIf(findings, spreadItem.subreddit_count >= 2, `It spread across ${spreadItem.subreddit_count} subreddits.`);
  pushIf(findings, spreadItem.author_count >= 2, `It was carried by ${spreadItem.author_count} distinct authors.`);
  pushIf(findings, !!spreadItem.first_seen && !!spreadItem.last_seen, `Observed window: ${spreadItem.first_seen} to ${spreadItem.last_seen}.`);
  pushIf(findings, spreadItem.span_minutes > 0, `Spread span is ${round2(spreadItem.span_minutes)} minutes.`);
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
  if (cluster.label) parts.push(`Shared framing: ${cluster.label}.`);
  if (cluster.size >= 2) parts.push(`${cluster.size} related posts detected.`);
  if ((cluster.subreddits || []).length >= 2) parts.push(`Spread across ${cluster.subreddits.length} subreddits.`);
  if ((cluster.average_narrative_steering_likelihood || 0) >= 0.6) parts.push('Steering signal is elevated.');
  if (cluster.baseline && (cluster.baseline.steering_delta || 0) > 0.1) parts.push('This exceeds local steering baseline.');
  return parts.join(' ');
}

function buildNarrativeSummary(item) {
  const parts = [];
  if (item.label) parts.push(`Narrative: ${item.label}.`);
  parts.push(`Seen in ${item.post_ids.length} posts.`);
  if (item.subreddit_count >= 2) parts.push(`Spread across ${item.subreddit_count} subreddits.`);
  if (item.time_compression_flag) parts.push('Appeared in a compressed time window.');
  return parts.join(' ');
}

export function buildAllFindings(clusters, spread) {
  return {
    cluster_findings: clusters.map(buildClusterFinding),
    narrative_findings: spread.map(buildNarrativeFinding)
  };
}
