begin;
create or replace function public.demo_guard_holiday_reschedule()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status in ('awaiting_slip','pending_review') then
    perform pg_advisory_xact_lock(hashtextextended('demo-holiday-' || new.new_slot_date::text, 0));
    if exists(select 1 from public.demo_holidays where day=new.new_slot_date) then
      raise exception 'HOLIDAY_CLOSED';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists demo_guard_holiday_reschedule on public.demo_reschedule_requests;
create trigger demo_guard_holiday_reschedule before insert or update of new_slot_date,status
  on public.demo_reschedule_requests for each row
  execute function public.demo_guard_holiday_reschedule();
commit;
