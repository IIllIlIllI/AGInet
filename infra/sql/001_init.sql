create table if not exists contents(
content_id text primary key,
subreddit text,
author_id text,
body_text text,
created_at timestamptz default now()
);
