begin;

create schema if not exists private;
revoke all on schema private from public;

drop trigger if exists demo_release_expired_hold_before_insert on public.demo_bookings;
drop trigger if exists demo_sync_slot_hold_after_change on public.demo_bookings;
drop trigger if exists demo_sync_slot_hold_after_update on public.demo_bookings;

create or replace function private.demo_release_expired_hold_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.demo_bookings
  set status = 'expired'
  where slot_date = new.slot_date
    and start_time = new.start_time
    and status = 'pending'
    and expires_at <= now();
  return new;
end;
$$;

create or replace function private.demo_sync_slot_hold_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    update public.demo_slots slot
    set hold_expires_at = (
      select max(booking.expires_at)
      from public.demo_bookings booking
      where booking.slot_date = old.slot_date
        and booking.start_time = old.start_time
        and booking.status = 'pending'
        and booking.expires_at > now()
    ), updated_at = now()
    where slot.slot_date = old.slot_date and slot.start_time = old.start_time;
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    update public.demo_slots slot
    set hold_expires_at = (
      select max(booking.expires_at)
      from public.demo_bookings booking
      where booking.slot_date = new.slot_date
        and booking.start_time = new.start_time
        and booking.status = 'pending'
        and booking.expires_at > now()
    ), updated_at = now()
    where slot.slot_date = new.slot_date and slot.start_time = new.start_time;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function private.demo_release_expired_hold_before_insert() from public, anon, authenticated;
revoke all on function private.demo_sync_slot_hold_state() from public, anon, authenticated;

create trigger demo_release_expired_hold_before_insert
before insert on public.demo_bookings
for each row execute function private.demo_release_expired_hold_before_insert();

create trigger demo_sync_slot_hold_after_change
after insert or delete on public.demo_bookings
for each row execute function private.demo_sync_slot_hold_state();

create trigger demo_sync_slot_hold_after_update
after update of status, expires_at, slot_date, start_time on public.demo_bookings
for each row execute function private.demo_sync_slot_hold_state();

drop function if exists public.demo_release_expired_hold_before_insert();
drop function if exists public.demo_sync_slot_hold_state();

commit;
