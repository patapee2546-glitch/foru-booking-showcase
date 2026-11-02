begin;

alter table public.demo_bookings
  alter column expires_at set default (now() + interval '5 minutes');

-- Keep older cached clients safe: even if they still submit a 10-minute
-- expiry, the database is the source of truth and shortens it to 5 minutes.
create or replace function public.demo_force_five_minute_booking_expiry()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status = 'pending' then
    new.expires_at := statement_timestamp() + interval '5 minutes';
  end if;
  return new;
end;
$$;

drop trigger if exists demo_force_five_minute_booking_expiry
  on public.demo_bookings;
create trigger demo_force_five_minute_booking_expiry
before insert on public.demo_bookings
for each row
execute function public.demo_force_five_minute_booking_expiry();

drop policy if exists demo_bookings_insert_self_pending on public.demo_bookings;
create policy demo_bookings_insert_self_pending
  on public.demo_bookings for insert
  to authenticated
  with check (
    customer_id = (select auth.uid())
    and status = 'pending'
    and removal_service in ('gel','pvc','none')
    and slip_path is null
    and slip_uploaded_at is null
    and cancelled_at is null
    and cancelled_by is null
    and cancelled_by_role is null
    and refund_status is null
    and created_at between now() - interval '5 seconds' and now() + interval '5 seconds'
    and expires_at > now()
    and expires_at <= now() + interval '5 minutes 5 seconds'
    and exists (
      select 1 from public.demo_slots s
      where s.slot_date = demo_bookings.slot_date
        and s.start_time = demo_bookings.start_time
        and s.is_open
    )
  );

commit;
