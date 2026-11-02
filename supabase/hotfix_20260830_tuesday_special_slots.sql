begin;

alter table public.demo_slots
  drop constraint if exists demo_slots_approved_periods;

alter table public.demo_slots
  add constraint demo_slots_approved_periods check (
    (start_time = time '10:00' and end_time = time '12:30') or
    (start_time = time '13:30' and end_time = time '16:00') or
    (extract(isodow from slot_date) = 2 and start_time = time '15:00' and end_time = time '17:30') or
    (start_time = time '17:00' and end_time = time '19:30') or
    (extract(isodow from slot_date) = 2 and start_time = time '19:00' and end_time = time '21:00') or
    (start_time = time '20:00' and end_time = time '22:30')
  );

alter table public.demo_bookings
  drop constraint if exists demo_bookings_approved_start_times;

alter table public.demo_bookings
  add constraint demo_bookings_approved_start_times check (
    start_time in (time '10:00', time '13:30', time '17:00', time '20:00') or
    (extract(isodow from slot_date) = 2 and start_time in (time '15:00', time '19:00'))
  );

commit;
