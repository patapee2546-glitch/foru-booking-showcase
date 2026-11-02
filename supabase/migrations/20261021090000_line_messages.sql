-- Every chat message from now on (LINE's API can't fetch past history), so the For U console can show a thread
-- without opening the chat in LINE OA Manager. 'in' = written by the webhook, 'out' = sent from the console.
-- Service role only, like demo_line_chats.
create table if not exists public.demo_line_messages (
  id bigint generated always as identity primary key,
  line_user_id text not null,
  at timestamptz not null default now(),
  dir text not null check (dir in ('in', 'out')),
  text text not null
);
create index if not exists demo_line_messages_user_at_idx on public.demo_line_messages (line_user_id, at);
alter table public.demo_line_messages enable row level security;
revoke all on public.demo_line_messages from anon, authenticated;
