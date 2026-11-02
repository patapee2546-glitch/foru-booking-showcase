from pathlib import Path


sql = Path("supabase/hotfix_20260830_first_click_hold.sql").read_text()

required = [
    "hold_expires_at timestamptz",
    "where status in ('pending', 'approved')",
    "before insert on public.demo_bookings",
    "status = 'expired'",
    "demo_sync_slot_hold_state",
    "create schema if not exists private",
    "security definer",
    "revoke all on function private.demo_sync_slot_hold_state() from public, anon, authenticated",
]

for token in required:
    assert token in sql, f"missing slot-hold contract: {token}"

print("first-click slot hold schema contract: passed")
