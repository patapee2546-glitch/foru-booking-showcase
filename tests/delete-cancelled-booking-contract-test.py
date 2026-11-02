from pathlib import Path

source = Path("supabase/functions/delete-cancelled-booking/index.ts").read_text(encoding="utf-8")
required = [
    "appMetadata?.role !== 'owner'",
    "ctx.jwtClaims?.app_metadata",
    "booking.status !== 'cancelled'",
    ".remove([booking.slip_path])",
    ".delete().eq('id', bookingId).eq('status', 'cancelled')",
]
missing = [item for item in required if item not in source]
assert not missing, f"delete-cancelled-booking safety contract missing: {missing}"
assert source.index("booking.status !== 'cancelled'") < source.index(".remove([booking.slip_path])")
assert source.index(".remove([booking.slip_path])") < source.index(".delete().eq('id', bookingId)")
print("delete cancelled booking contract: passed")
