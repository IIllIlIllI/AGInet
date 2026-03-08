export async function fetchSubredditNew(subreddit) {
  const now = new Date().toISOString();
  return [
    {
      id: `demo-${subreddit}-1`,
      subreddit,
      author: 'demo_user_alpha',
      title: `A discussion thread in r/${subreddit}`,
      body: `I think people are overreacting. We should take a balanced view and consider all sides carefully. This may be more coordinated than it seems.`,
      created_at: now,
      permalink: `/r/${subreddit}/comments/demo-${subreddit}-1`
    },
    {
      id: `demo-${subreddit}-2`,
      subreddit,
      author: 'demo_user_beta',
      title: `Another thread in r/${subreddit}`,
      body: `Everyone knows this is manipulated. Clearly the whole thing is compromised and nobody can trust it anymore.`,
      created_at: now,
      permalink: `/r/${subreddit}/comments/demo-${subreddit}-2`
    }
  ];
}
