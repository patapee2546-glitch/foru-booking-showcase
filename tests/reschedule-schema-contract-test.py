from pathlib import Path

schema = Path('supabase/schema.sql').read_text()
sql = schema.lower()

required = [
    'create table public.demo_reschedule_requests',
    'create table public.demo_booking_reschedule_history',
    "status in ('awaiting_slip','pending_review','approved','rejected','expired','cancelled')",
    'fee_amount integer not null default 20',
    'demo_reschedule_active_new_slot_unique',
    "where status in ('awaiting_slip','pending_review')",
    'demo_reschedule_one_active_per_booking',
    'alter table public.demo_reschedule_requests enable row level security',
    'alter table public.demo_booking_reschedule_history enable row level security',
    'customer_id = (select auth.uid())',
    "auth.jwt()->'app_metadata'->>'role'",
    'create or replace function public.review_demo_reschedule',
    'create or replace function public.expire_demo_reschedules',
    "'demo-reschedule-slips'",
    'alter publication supabase_realtime add table public.demo_reschedule_requests',
    'revoke all on function public.review_demo_reschedule',
    'grant execute on function public.review_demo_reschedule',
]

for needle in required:
    assert needle in sql, f'missing reschedule schema contract: {needle}'

assert 'security invoker' in sql, 'atomic RPC must use the server-side service role without definer escalation'
assert 'for update' in sql, 'review RPC must lock rows before moving a booking'
assert "with check (new.status = 'approved')" not in sql, 'RLS must not trust client-provided approved status'

hotfix = Path('supabase/reschedule_20260830.sql')
assert hotfix.exists(), 'missing idempotent live schema update script'
hotfix_sql = hotfix.read_text().lower()
for needle in ('create table if not exists public.demo_reschedule_requests',
               'create or replace function public.review_demo_reschedule',
               'create or replace function public.expire_demo_reschedules'):
    assert needle in hotfix_sql, f'missing live update contract: {needle}'

print('reschedule schema contract: passed')
