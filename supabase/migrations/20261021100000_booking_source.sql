-- Where a booking came from: the ?ref= on the booking link (ig, fb, tiktok, line, ...), saved by create-booking.
-- Null = opened the page without a ref (direct, bookmark, old link).
alter table public.demo_bookings add column if not exists source text;
alter table public.demo_bookings drop constraint if exists demo_bookings_source_check;
alter table public.demo_bookings add constraint demo_bookings_source_check check (source is null or source ~ '^[a-z0-9_-]{1,30}$');
