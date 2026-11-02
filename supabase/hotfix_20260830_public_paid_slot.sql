begin;

alter table public.demo_slots
  add column if not exists is_booked boolean not null default false;

create or replace function public.demo_sync_slot_booking_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.status = 'approved'
    and (new.status <> 'approved' or old.slot_date <> new.slot_date or old.start_time <> new.start_time) then
    update public.demo_slots s
    set is_booked = exists (
      select 1 from public.demo_bookings b
      where b.slot_date = old.slot_date and b.start_time = old.start_time and b.status = 'approved'
    ), updated_at = now()
    where s.slot_date = old.slot_date and s.start_time = old.start_time;
  end if;

  if new.status = 'approved' then
    update public.demo_slots
    set is_open = false, is_booked = true, updated_at = now()
    where slot_date = new.slot_date and start_time = new.start_time;
  end if;
  return new;
end;
$$;

drop trigger if exists demo_sync_slot_booking_state on public.demo_bookings;
create trigger demo_sync_slot_booking_state
after insert or update of status, slot_date, start_time on public.demo_bookings
for each row execute function public.demo_sync_slot_booking_state();

update public.demo_slots s
set is_booked = exists (
  select 1 from public.demo_bookings b
  where b.slot_date = s.slot_date and b.start_time = s.start_time and b.status = 'approved'
),
is_open = case
  when exists (
    select 1 from public.demo_bookings b
    where b.slot_date = s.slot_date and b.start_time = s.start_time and b.status = 'approved'
  ) then false
  else s.is_open
end,
updated_at = now();

commit;
