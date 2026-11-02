from pathlib import Path

sql_path = Path("supabase/schema.sql")
sql = sql_path.read_text(encoding="utf-8") if sql_path.exists() else ""
required = [
    "create table public.demo_slots",
    "create table public.demo_bookings",
    "enable row level security",
    "revoke all on table",
    "create unique index demo_one_active_booking_per_slot",
    "grant select on table public.demo_bookings to authenticated",
    "alter publication supabase_realtime add table public.demo_slots",
    "alter publication supabase_realtime add table public.demo_bookings",
    "removal_service text not null",
    "slip_path text",
    "slip_uploaded_at timestamptz",
    "cancelled_at timestamptz",
    "cancelled_by uuid",
    "cancelled_by_role text",
    "refund_status text",
    "demo-payment-slips",
    "image/jpeg",
    "image/png",
    "image/webp",
]
missing = [item for item in required if item not in sql.lower()]
assert not missing, f"missing schema contracts: {missing}"

for unsafe in [
    "user_metadata",
    "public = true",
    "grant insert on table public.demo_bookings to authenticated",
    "grant update on table public.demo_bookings to authenticated",
]:
    assert unsafe not in sql.lower(), f"unsafe schema token present: {unsafe}"

assert "security definer" not in sql.lower(), "schema must avoid definer privilege escalation"

print("schema contract: passed")
