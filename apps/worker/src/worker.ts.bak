import { fetchSubredditNew } from '../../../packages/reddit/src/fetch.ts';
import { extractContentFeatures } from '../../../packages/features/src/index.js';
import { scoreContent } from '../../../packages/scoring/src/index.js';
import { savePost, saveAnalysis } from '../../../packages/storage/src/storage.js';

const SUBS = (process.env.PILOT_SUBREDDITS ?? 'technology,news,gaming')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

async function main() {
  console.log('Truth Lens worker started');
  console.log('Pilot subreddits:', SUBS.join(', '));

  for (const subreddit of SUBS) {
    const posts = await fetchSubredditNew(subreddit);

    for (const post of posts) {
      savePost(post);
      const features = extractContentFeatures(post);
      const score = scoreContent(post, features);

      saveAnalysis({
        id: post.id,
        post,
        features,
        score,
        analyzed_at: new Date().toISOString()
      });

      console.log(`[saved] ${post.id}`);
      console.log(`[scored] ${post.id} synthetic=${score.synthetic_language_likelihood} steering=${score.narrative_steering_likelihood} coordination=${score.coordination_likelihood}`);
    }
  }

  console.log('Worker cycle complete');
}

main().catch((err) => {
  console.error('Worker failed:', err);
  process.exit(1);
});
