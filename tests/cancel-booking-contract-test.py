from pathlib import Path


path = Path("supabase/functions/cancel-booking/index.ts")
assert path.exists(), "missing cancel-booking Edge Function"
code = path.read_text(encoding="utf-8")
deno_config = Path("supabase/functions/cancel-booking/deno.json")
assert deno_config.exists(), "missing cancel-booking runtime configuration"
deno_text = deno_config.read_text(encoding="utf-8")

required = [
    "withSupabase({ auth: 'user' }",
    "bookingId",
    "app_metadata",
    "Asia/Bangkok",
    "48 * 60 * 60 * 1000",
    "refund_due",
    "no_refund",
    "status: 'cancelled'",
    "cancelled_by_role",
    "ctx.jwtClaims?.app_metadata",
    ".update({ is_open: true",
]
missing = [item for item in required if item not in code]
assert not missing, f"cancel-booking missing contracts: {missing}"

uuid_guard = "if (!bookingId || !UUID_PATTERN.test(bookingId) || !userId)"
assert uuid_guard in code, "cancel-booking must reject malformed non-empty bookingId values"
assert code.index(uuid_guard) < code.index(".from('demo_bookings')"), \
    "cancel-booking must validate bookingId before the first database query"
assert code.index("if (cancelledBooking)") < code.index(".update({ is_open: true"), \
    "cancel-booking must reopen only after cancellation succeeds"

assert "from '@supabase/server'" in code, "cancel-booking must use its mapped pinned Supabase runtime"
assert "npm:@supabase/server@1.4.1" in deno_text, "cancel-booking must pin the Supabase runtime exactly"
assert "^" not in deno_text, "cancel-booking runtime dependency must not use a semver range"

print("cancel-booking contract: passed")
