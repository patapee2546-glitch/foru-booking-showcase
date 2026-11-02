from pathlib import Path


sql = Path("supabase/schema.sql").read_text(encoding="utf-8").lower()

required = [
    "create table public.demo_line_links",
    "line_user_id text not null unique",
    "create table public.demo_booking_line_recipients",
    "create table public.demo_line_notifications",
    "recipient_line_user_id text not null",
    "unique (booking_id, notification_type)",
    "create or replace function public.demo_link_line_customer",
    "create or replace function public.demo_create_pending_booking",
    "create or replace function public.demo_claim_booking_and_enqueue",
    "create or replace function public.demo_claim_due_line_notifications",
    "create or replace function public.demo_claim_line_notification",
    "create or replace function public.demo_finish_line_notification",
    "create or replace function public.demo_cancel_line_notification",
    "interval '1 hour'",
    "asia/bangkok",
]

missing = [token for token in required if token not in sql]
assert not missing, f"missing LINE notification schema contracts: {missing}"

unsafe_grants = [
    "grant insert on table public.demo_line_links to authenticated",
    "grant select on table public.demo_line_links to authenticated",
    "grant select on table public.demo_booking_line_recipients to authenticated",
    "grant insert on table public.demo_bookings to authenticated",
]
present = [token for token in unsafe_grants if token in sql]
assert not present, f"unsafe LINE/booking grants present: {present}"

line_rpcs = {
    "demo_link_line_customer",
    "demo_create_pending_booking",
    "demo_claim_booking_and_enqueue",
    "demo_claim_due_line_notifications",
    "demo_claim_line_notification",
    "demo_finish_line_notification",
    "demo_cancel_line_notification",
}
assert "security definer" not in sql
for function_name in line_rpcs:
    function_start = sql.index(f"create or replace function public.{function_name}")
    function_body = sql[function_start:function_start + 1400]
    assert "security invoker" in function_body
    assert "set search_path = ''" in function_body
    assert f"revoke all on function public.{function_name}" in sql
    assert f"grant execute on function public.{function_name}" in sql

print("line notification schema contract: passed")
