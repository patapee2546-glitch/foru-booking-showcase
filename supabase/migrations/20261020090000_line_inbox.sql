-- Chats customers send to the shop's LINE OA, written by the line-webhook function.
-- One row per customer: the latest message, and when the shop last answered from the For U LINE console.
-- Service role only (no policies): the customer page never reads it.
create table if not exists public.demo_line_chats (
  line_user_id text primary key,
  display_name text,
  picture_url text,
  last_text text,
  last_at timestamptz not null default now(),
  unanswered_count integer not null default 0,
  replied_at timestamptz
);
create index if not exists demo_line_chats_last_at_idx on public.demo_line_chats (last_at desc);
alter table public.demo_line_chats enable row level security;
revoke all on public.demo_line_chats from anon, authenticated;
