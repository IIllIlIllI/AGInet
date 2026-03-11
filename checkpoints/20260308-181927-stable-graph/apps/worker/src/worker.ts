import { fetchSubredditNew } from '../../../packages/reddit/src/fetch.ts';
import { extractContentFeatures } from '../../../packages/features/src/index.js';
import { scoreContent } from '../../../packages/scoring/src/index.js';
import {
  savePost,
  saveAnalysis,
  getIngestState,
  updateIngestState
} from '../../../packages/storage/src/storage.js';

const SUBS = (process.env.PILOT_SUBREDDITS ?? 'technology,news,gaming')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

async function main() {
  console.log('Truth Lens worker started');
  console.log('Pilot subreddits:', SUBS.join(', '));

  const ingestState = getIngestState();
  console.log('Last run:', ingestState.last_run_at || 'never');

  for (const subreddit of SUBS) {
    console.log(`\n[fetch] r/${subreddit}`);
    const posts = await fetchSubredditNew(subreddit);

    let created = 0;
    let updated = 0;

    for (const rawPost of posts) {
      const saved = savePost(rawPost);
      const post = saved.post;

      if (saved.status === 'created') created += 1;
      if (saved.status === 'updated') updated += 1;

      const features = extractContentFeatures(post);
      const score = scoreContent(post, features);

      saveAnalysis({
        id: post.id,
        post,
        features,
        score
      });

      console.log(
        `[${saved.status}] ${post.id} synthetic=${score.synthetic_language_likelihood} steering=${score.narrative_steering_likelihood} coordination=${score.coordination_likelihood}`
      );
    }

    updateIngestState(subreddit, {
      fetched_count: posts.length,
      created_count: created,
      updated_count: updated,
      latest_ids: posts.slice(0, 5).map((p) => p.id)
    });

    console.log(
      `[done] r/${subreddit} fetched=${posts.length} created=${created} updated=${updated}`
    );
  }

  console.log('\nWorker cycle complete');
}

main().catch((err) => {
  console.error('Worker failed:', err);
  process.exit(1);
});
