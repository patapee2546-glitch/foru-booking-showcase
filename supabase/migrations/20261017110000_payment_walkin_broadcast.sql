-- Medium batch 2 (2026-10-17), apply after 20261017100000_medium_batch.sql. Not applied yet.

-- #1 + #2 Slip check, option A: the booking is confirmed at once, the owner verifies the slip afterwards
alter table public.demo_bookings add column if not exists payment_status text
  check (payment_status in ('unverified','verified','rejected','walk_in'));
alter table public.demo_bookings add column if not exists payment_checked_at timestamptz;
-- every paid booking starts as "รอตรวจสลิป"
update public.demo_bookings set payment_status = 'unverified' where status = 'approved' and payment_status is null and slip_path is not null;

create or replace function private.demo_mark_payment_unverified()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' and new.payment_status is null then
    new.payment_status := 'unverified';
  end if;
  return new;
end $$;
drop trigger if exists demo_mark_payment_unverified on public.demo_bookings;
create trigger demo_mark_payment_unverified before update of status on public.demo_bookings
for each row execute function private.demo_mark_payment_unverified();

create or replace function public.demo_verify_payment(p_booking_id uuid, p_ok boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'owner' then raise exception 'OWNER_REQUIRED'; end if;
  update public.demo_bookings
    set payment_status = case when p_ok then 'verified' else 'rejected' end, payment_checked_at = statement_timestamp()
    where id = p_booking_id and status = 'approved' and payment_status in ('unverified','verified','rejected');
  if not found then raise exception 'BOOKING_NOT_VERIFIABLE'; end if;
end $$;
revoke all on function public.demo_verify_payment(uuid,boolean) from public, anon;
grant execute on function public.demo_verify_payment(uuid,boolean) to authenticated;

-- #3 Owner books a walk-in / phone customer: no LINE, no slip, pays at the shop
create or replace function public.demo_owner_create_booking(
  p_slot_date date, p_start_time time, p_name text, p_phone text, p_service text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'owner' then raise exception 'OWNER_REQUIRED'; end if;
  perform 1 from public.demo_slots where slot_date = p_slot_date and start_time = p_start_time for update;
  if not found then raise exception 'SLOT_NOT_FOUND'; end if;
  -- the unique index demo_one_active_booking_per_slot rejects a slot that already has a pending/approved booking
  insert into public.demo_bookings(customer_id, slot_date, start_time, customer_name, customer_phone, removal_service, status, payment_status)
  values ((select auth.uid()), p_slot_date, p_start_time, btrim(p_name), regexp_replace(p_phone, '[^0-9]', '', 'g'), p_service, 'approved', 'walk_in')
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.demo_owner_create_booking(date,time,text,text,text) from public, anon;
grant execute on function public.demo_owner_create_booking(date,time,text,text,text) to authenticated;

-- #4 Monthly income: the owner may read what was collected at the shop
grant select on public.demo_service_settlements to authenticated;
drop policy if exists demo_settlements_owner_read on public.demo_service_settlements;
create policy demo_settlements_owner_read on public.demo_service_settlements for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');

-- #5 Scheduled LINE promo to past customers (shows as a phone notification from the shop's LINE)
create table if not exists public.demo_promo_broadcasts (
  id uuid primary key default gen_random_uuid(),
  message text not null check (char_length(btrim(message)) between 1 and 500),
  send_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','sending','sent','cancelled','failed')),
  recipients integer,
  sent_count integer,
  created_at timestamptz not null default now()
);
alter table public.demo_promo_broadcasts enable row level security;
grant select, insert, update on public.demo_promo_broadcasts to authenticated;
create policy demo_broadcasts_owner on public.demo_promo_broadcasts for all to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');

-- audience: LINE users with at least one paid visit in the past that was not a no-show
create or replace function public.demo_broadcast_audience()
returns table(line_user_id text) language sql security definer set search_path = '' as $$
  select distinct r.line_user_id
  from public.demo_booking_line_recipients r
  join public.demo_bookings b on b.id = r.booking_id
  where b.status = 'approved' and b.slot_date < (now() at time zone 'Asia/Bangkok')::date
    and b.attendance is distinct from 'no_show';
$$;
revoke all on function public.demo_broadcast_audience() from public, anon, authenticated;
grant execute on function public.demo_broadcast_audience() to service_role;

create or replace function public.demo_broadcast_audience_count()
returns integer language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'owner' then raise exception 'OWNER_REQUIRED'; end if;
  return (select count(*) from public.demo_broadcast_audience());
end $$;
revoke all on function public.demo_broadcast_audience_count() from public, anon;
grant execute on function public.demo_broadcast_audience_count() to authenticated;

-- LINE messages sent this calendar month (owner sees how much free quota is left)
create or replace function public.demo_line_messages_this_month()
returns integer language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'owner' then raise exception 'OWNER_REQUIRED'; end if;
  return (select count(*) from public.demo_line_notifications where status = 'sent' and sent_at >= date_trunc('month', now()))
       + coalesce((select sum(sent_count) from public.demo_promo_broadcasts where status = 'sent' and send_at >= date_trunc('month', now())), 0);
end $$;
revoke all on function public.demo_line_messages_this_month() from public, anon;
grant execute on function public.demo_line_messages_this_month() to authenticated;

-- the minute cron claims due broadcasts one at a time
create or replace function public.demo_claim_due_broadcast()
returns public.demo_promo_broadcasts language plpgsql security invoker set search_path = '' as $$
declare v public.demo_promo_broadcasts%rowtype;
begin
  update public.demo_promo_broadcasts set status = 'sending'
  where id = (select id from public.demo_promo_broadcasts where status = 'pending' and send_at <= now() order by send_at limit 1 for update skip locked)
  returning * into v;
  return v;
end $$;
revoke all on function public.demo_claim_due_broadcast() from public, anon, authenticated;
grant execute on function public.demo_claim_due_broadcast() to service_role;
